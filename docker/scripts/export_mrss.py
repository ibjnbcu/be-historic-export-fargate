#!/usr/bin/env python3
import sys
import json

# Read JSON payload from stdin (produced by: yq -p=xml -o=json)
input_read = sys.stdin.read()
root_in = json.loads(input_read)

channel = root_in.get('rss', {}).get('channel', {})

def as_int(value):
    try:
        return int(str(value).strip(), 10)
    except (TypeError, ValueError):
        return None

def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]

def get_first(d, *keys, default=None):
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(k)
    return cur if cur is not None else default

def text_value(v):
    """
    Extract text content from yq xml-converted values.
    - str => stripped str
    - dict => uses +content / #text
    """
    if v is None:
        return None
    if isinstance(v, str):
        s = v.strip()
        return s if s else None
    if isinstance(v, dict):
        s = (v.get('+content') or v.get('#text') or '')
        s = s.strip() if isinstance(s, str) else ''
        return s if s else None
    return None

# -------------------------
# Channel-level normalization
# -------------------------
link = channel.get('link', '')
image = channel.get('image', {})

link_text = ''
link_attrs = {}

# Normalize channel.link which can be str | list | dict
if isinstance(link, str):
    link_text = link
elif isinstance(link, list):
    if len(link) > 0 and isinstance(link[0], str):
        link_text = link[0]
    if len(link) > 1 and isinstance(link[1], dict):
        link_attrs = link[1]
elif isinstance(link, dict):
    link_text = link.get('+content') or link.get('#text') or ''
    link_attrs = link

base_row = {
    "title": channel.get('title', ''),
    "link": link_text,
    "copyright": channel.get('copyright'),
    "language": channel.get('language'),
    "pubDate": channel.get('pubDate'),
    "lastBuildDate": channel.get('lastBuildDate'),
    "generator": channel.get('generator'),
}

items = channel.get('item')
if not items:
    # Fail loudly; caller can see the raw payload
    print(input_read)
    sys.exit(1)

out = []

for item in as_list(items):
    # -------------------------
    # Guid normalization
    # -------------------------
    guid_obj = item.get('guid')
    guid_is_permalink = None
    guid_val = None
    if isinstance(guid_obj, dict):
        guid_is_permalink = guid_obj.get('+@isPermaLink') or guid_obj.get('@isPermaLink')
        guid_val = text_value(guid_obj)
    else:
        guid_val = text_value(guid_obj)

    # -------------------------
    # MRSS (media:group) parsing
    # -------------------------
    media_group = item.get('media:group') or {}
    media_contents = as_list(media_group.get('media:content'))
    media_thumbs = as_list(media_group.get('media:thumbnail'))

    # Choose best media:content (prefer medium=video, else first)
    content_url = None
    content_medium = None
    content_type = None
    content_lang = None

    chosen = None
    for c in media_contents:
        if isinstance(c, dict) and ((c.get('+@medium') or c.get('@medium')) == 'video'):
            chosen = c
            break
    if chosen is None:
        chosen = media_contents[0] if (media_contents and isinstance(media_contents[0], dict)) else None

    if chosen:
        content_url = chosen.get('+@url') or chosen.get('@url')
        content_medium = chosen.get('+@medium') or chosen.get('@medium')
        content_type = chosen.get('+@type') or chosen.get('@type')
        content_lang = chosen.get('+@lang') or chosen.get('@lang')

    # If not found, look for document-type media content
    if not content_lang:
        for c in media_contents:
            if isinstance(c, dict) and (
                (c.get('+@medium') or c.get('@medium')) == 'document'
                or (c.get('+@type') or c.get('@type')) == 'application/ttml+xml'
            ):
                content_lang = c.get('+@lang') or c.get('@lang')
                if content_lang:
                    break

    # Thumbnail (first)
    thumb0 = media_thumbs[0] if (media_thumbs and isinstance(media_thumbs[0], dict)) else {}
    thumb_url = thumb0.get('+@url') or thumb0.get('@url')
    thumb_w = as_int(thumb0.get('+@width') or thumb0.get('@width')) or 0
    thumb_h = as_int(thumb0.get('+@height') or thumb0.get('@height')) or 0

    # -------------------------
    # Build output row
    # -------------------------
    out_item = base_row.copy()

    out_item['item_title'] = item.get('title')
    out_item['item_mpx_title'] = item.get('nbc:mpx_title')

    out_item['item_link'] = item.get('link')
    out_item['item_canonical_url'] = item.get('canonical_url')

    out_item['item_guid_isPermaLink'] = guid_is_permalink
    out_item['item_guid'] = guid_val

    # Creator
    out_item['item_creator'] = item.get('dc:creator')

    # Station / IDs
    out_item['item_station_id'] = as_int(item.get('nbc:station_id'))

    out_item['item_syndication_id'] = item.get('media:syndication_id')
    out_item["item_formatted_syndication_id"] = text_value(
        item.get("nbc:formatted_syndication_id") or item.get("media:formatted_syndication_id")
    ) or None

    # Taxonomy / metadata
    out_item['item_category'] = item.get('media:category')
    out_item['item_categories'] = item.get('media:categories')
    out_item['item_tags'] = item.get('media:tags')
    out_item['item_collections'] = item.get('media:collections')
    out_item['item_primary_category'] = item.get('media:primary_category')
    out_item['item_primary_tag'] = item.get('media:primary_tag')
    out_item['item_sentiment'] = item.get('media:sentiment')

    # Calls / video metadata
    out_item['item_call_letters'] = item.get('media:call_letters')
    out_item['item_parent_call_letters'] = item.get('media:parent_call_letters')
    out_item['item_video_id'] = item.get('media:video_id')
    out_item['item_video_duration'] = as_int(item.get('media:video_duration'))
    out_item['item_source'] = item.get('media:source')
    out_item['item_youtube_id'] = item.get('media:youtube_id')

    # Media outputs
    out_item['item_content_url'] = content_url
    out_item['item_content_medium'] = content_medium
    out_item['item_content_type'] = content_type
    out_item['item_content_lang'] = content_lang

    out_item['item_thumbnail_url'] = thumb_url
    out_item['item_thumbnail_width'] = thumb_w
    out_item['item_thumbnail_height'] = thumb_h

    # Text fields
    out_item['item_excerpt'] = item.get('excerpt')
    out_item['item_description'] = item.get('description')
    out_item['item_pubDate'] = item.get('pubDate')
    out_item['item_updateDate'] = item.get('updateDate')

    out.append(out_item)

print(json.dumps(out))