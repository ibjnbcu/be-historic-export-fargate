#!/usr/bin/env python3
import sys
import json

def as_dict(x):
    return x if isinstance(x, dict) else {}

def as_list(x):
    if x is None:
        return []
    return x if isinstance(x, list) else [x]

def text_value(node) -> str:
    """
    Extract text from common xml->json shapes.
    Handles:
      - "text"
      - {"#text": "..."} or {"+content": "..."}
      - {"$t": "..."} (some converters)
      - ["text", {...}]
      - {"0": "..."} oddities fall back to str(node)
    """
    if node is None:
        return ""
    if isinstance(node, str):
        return node.strip()
    if isinstance(node, (int, float)):
        return str(node)
    if isinstance(node, (list, tuple)):
        if not node:
            return ""
        # often ["text", {attrs}]
        return text_value(node[0])
    if isinstance(node, dict):
        # common keys for text
        for k in ("#text", "+content", "$t", "content"):
            if k in node and isinstance(node[k], (str, int, float)):
                return str(node[k]).strip()
        # if dict is actually just attrs (no text), return ""
        return ""
    return str(node).strip()


def attrs_value(node) -> dict:
    """
    Extract attribute dict from common xml->json shapes.
    Handles:
      - {"@href": "..."} or {"+@href": "..."}
      - ["text", {attrs}]
      - {"$": {attrs}} (some converters)
    """
    if node is None:
        return {}
    if isinstance(node, (list, tuple)):
        # often ["text", {attrs}]
        if len(node) == 2 and isinstance(node[1], dict):
            return node[1]
        if node:
            return attrs_value(node[0])
        return {}
    if isinstance(node, dict):
        if "$" in node and isinstance(node["$"], dict):
            return node["$"]
        # collect keys that look like attrs
        out = {}
        for k, v in node.items():
            if isinstance(k, str) and (k.startswith("@") or k.startswith("+@")):
                out[k] = v
        return out
    return {}


def get_attr(attrs: dict, name: str):
    # accepts "href" and looks for "+@href" then "@href"
    return attrs.get(f"+@{name}") or attrs.get(f"@{name}")


def to_int(x, default=None):
    try:
        s = text_value(x)
        if s == "":
            return default
        return int(s, 10)
    except Exception:
        return default


def first_thumbnail(content_dict: dict) -> dict:
    thumbs = content_dict.get("thumbnail")
    thumbs_list = as_list(thumbs)
    if not thumbs_list:
        return {}
    return as_dict(thumbs_list[0])


def main():
    input_read = sys.stdin.read()
    if not input_read.strip():
        print("No input on stdin", file=sys.stderr)
        sys.exit(2)

    try:
        root_in = json.loads(input_read)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON on stdin: {e}", file=sys.stderr)
        sys.exit(2)

    channel = as_dict(as_dict(root_in).get("rss", {})).get("channel", {})
    channel = as_dict(channel)

    # channel-level link can be string, dict, or ["text", {attrs}]
    link_node = channel.get("link")
    channel_link_text = text_value(link_node)
    channel_link_attrs = attrs_value(link_node)

    image = as_dict(channel.get("image"))

    base_row = {
        "title": text_value(channel.get("title")),
        "link": channel_link_text,
        "link_href": get_attr(channel_link_attrs, "href"),
        "link_rel": get_attr(channel_link_attrs, "rel"),
        "link_type": get_attr(channel_link_attrs, "type"),
        "copyright": text_value(channel.get("copyright")),
        "image_url": text_value(image.get("url")),
        "image_title": text_value(image.get("title")),
        "image_link": text_value(image.get("link")),
        "language": text_value(channel.get("language")),
        "pubDate": text_value(channel.get("pubDate")),
        "lastBuildDate": text_value(channel.get("lastBuildDate")),
        "generator": text_value(channel.get("generator")),
    }

    items = channel.get("item")
    if not items:
        # Keep your old behavior: dump input for debugging
        print(input_read)
        sys.exit(1)

    out = []
    for item in as_list(items):
        item = as_dict(item)
        out_item = base_row.copy()

        out_item["item_title"] = text_value(item.get("title"))
        out_item["item_link"] = text_value(item.get("link"))

        # Your sample has <guid isPermaLink="false"> 483 </guid>
        guid_node = item.get("guid")
        guid_text = text_value(guid_node)
        guid_attrs = attrs_value(guid_node)
        out_item["item_guid_isPermaLink"] = get_attr(guid_attrs, "isPermaLink")
        out_item["item_guid"] = to_int(guid_text, default=None)

        # Namespaced fields may come through as "nbc:station_id" etc depending on converter.
        out_item["item_station_id"] = to_int(item.get("nbc:station_id"), default=None)
        out_item["item_market_identifier"] = text_value(item.get("nbc:market_identifier")) or None
        out_item["item_content_id"] = to_int(item.get("nbc:content_id"), default=None)
        out_item["item_syndication_id"] = text_value(item.get("nbc:syndication_id")) or None
        # out_item["item_formatted_syndication_id"] = to_int(item.get("nbc:formatted_syndication_id"), default=None)
        out_item["item_formatted_syndication_id"] = text_value(item.get("nbc:formatted_syndication_id")) or None
        out_item["item_parent_call_letters"] = text_value(item.get("nbc:parent_call_letters")) or None
        out_item["item_canonical_url"] = text_value(item.get("nbc:canonical_url")) or text_value(item.get("canonical_url")) or None

        # dc:creator in your sample
        out_item["item_creator"] = text_value(item.get("dc:creator")) or text_value(item.get("creator")) or None

        out_item["item_primary_tag"] = text_value(item.get("nbc:primary_tag")) or None
        out_item["item_category"] = text_value(item.get("nbc:category")) or None
        out_item["item_categories"] = text_value(item.get("nbc:categories")) or None
        out_item["item_tags"] = text_value(item.get("nbc:tags")) or None

        # media:content often comes through as "content" or "media:content" depending on converter
        content = item.get("media:content") or item.get("content")
        content = as_dict(content)
        content_attrs = attrs_value(content)  # if converter stores attrs on same dict
        # some converters store attrs directly as "@url" etc inside content dict; attrs_value handles that

        out_item["item_content_url"] = get_attr(content_attrs, "url") or content.get("+@url") or content.get("@url")
        out_item["item_content_medium"] = get_attr(content_attrs, "medium") or content.get("+@medium") or content.get("@medium")

        # media:title and media:description can be dicts with attrs + CDATA text
        title_node = content.get("title") or content.get("media:title")
        title_attrs = attrs_value(title_node)
        out_item["item_title_type"] = get_attr(title_attrs, "type")

        desc_node = content.get("description") or content.get("media:description")
        desc_attrs = attrs_value(desc_node)
        out_item["item_description_type"] = get_attr(desc_attrs, "type")

        # thumbnail is usually self-closing with attrs only
        thumb0 = first_thumbnail(content)
        thumb0_attrs = attrs_value(thumb0)
        out_item["item_thumbnail_url"] = get_attr(thumb0_attrs, "url") or thumb0.get("+@url") or thumb0.get("@url")
        out_item["item_thumbnail_width"] = to_int(get_attr(thumb0_attrs, "width") or thumb0.get("+@width") or thumb0.get("@width"), default=0)
        out_item["item_thumbnail_height"] = to_int(get_attr(thumb0_attrs, "height") or thumb0.get("+@height") or thumb0.get("@height"), default=0)

        # keep extra thumbnail variants (e.g., photo:thumbnail) if present
        out_item["item_content_thumbnail"] = (
            text_value(content.get("photo:thumbnail"))
            or text_value(content.get("thumbnail"))
            or None
        )

        out_item["item_description"] = text_value(item.get("description")) or None
        out_item["item_excerpt"] = text_value(item.get("excerpt")) or None
        out_item["item_pubDate"] = text_value(item.get("pubDate")) or None
        out_item["item_updateDate"] = text_value(item.get("updateDate")) or None
        out_item["item_primary_category"] = text_value(item.get("primary_category")) or None

        out.append(out_item)

    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()