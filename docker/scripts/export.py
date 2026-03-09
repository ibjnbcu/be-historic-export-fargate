#!/usr/bin/env python
import sys
import json

input_read = sys.stdin.read()

# grab JSON payload from stdin.
root = json.loads(input_read)

channel = root.get('rss', {}).get('channel', {})

print(
    "DEBUG link type/value:",
    type(channel.get('link')).__name__,
    channel.get('link'),
    file=sys.stderr
)

def as_int(value):
    try:
        return int(value, 10)
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

link = channel.get('link', '')

image = channel.get('image', {})

# normalize link which can be str | list | dict
link_text = ''
link_attrs = {}

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

root = {
    "title": channel.get('title', ''),
    "link": link_text,
    "link_href": link_attrs.get('+@href') or link_attrs.get('@href'),
    "link_rel": link_attrs.get('+@rel') or link_attrs.get('@rel'),
    "link_type": link_attrs.get('+@type') or link_attrs.get('@type'),
    "copyright": channel.get('copyright'),
    "image_url": image.get('url'),
    "image_title": image.get('title'),
    "image_link": image.get('link'),
    "language": channel.get('language'),
    "pubDate": channel.get('pubDate'),
    "lastBuildDate": channel.get('lastBuildDate'),
    "generator": channel.get('generator'),
}

out = []

if not channel.get('item'):
	print(input_read)
	exit(1)

for item in channel.get('item'):

    # content can be either item['content'] OR inside media:group
    content = item.get('content')

    media_group = item.get('group') or item.get('media:group') or {}
    media_contents = as_list(media_group.get('content') or media_group.get('media:content'))
    media_thumbs = as_list(media_group.get('thumbnail') or media_group.get('media:thumbnail'))

    # Normalize "content" to something with attrs if possible
    content_url = None
    content_medium = None
    title_type = None
    description_type = None

    if isinstance(content, dict):
        content_url = content.get('+@url') or content.get('@url')
        content_medium = content.get('+@medium') or content.get('@medium')
        title_type = get_first(content, 'title', '+@type') or get_first(content, 'title', '@type')
        description_type = get_first(content, 'description', '+@type') or get_first(content, 'description', '@type')

    # If not present, fall back to media:group contents (prefer video)
    if content_url is None and media_contents:
        chosen = None
        for c in media_contents:
            if isinstance(c, dict) and ((c.get('+@medium') or c.get('@medium')) == 'video'):
                chosen = c
                break
        if chosen is None:
            chosen = media_contents[0] if isinstance(media_contents[0], dict) else None

        if chosen:
            content_url = chosen.get('+@url') or chosen.get('@url')
            content_medium = chosen.get('+@medium') or chosen.get('@medium')

    # Thumbnail: prefer first media thumbnail
    thumb0 = media_thumbs[0] if (media_thumbs and isinstance(media_thumbs[0], dict)) else {}
    thumb_url = thumb0.get('+@url') or thumb0.get('@url')
    thumb_w = as_int(thumb0.get('+@width') or thumb0.get('@width')) or 0
    thumb_h = as_int(thumb0.get('+@height') or thumb0.get('@height')) or 0

    out_item = root.copy()
    out_item['item_title'] = item.get('title')
    out_item['item_link'] = item.get('link')
    out_item['item_station_id'] = as_int(item.get('station_id'))
    out_item['item_market_identifier'] = item.get('market_identifier')
    out_item['item_content_id'] = as_int(item.get('content_id'))
    out_item['item_syndication_id'] = item.get('syndication_id')
    out_item['item_formatted_syndication_id'] = as_int(item.get('formatted_syndication_id'))
    out_item['item_parent_call_letters'] = item.get('parent_call_letters')
    out_item['item_canonical_url'] = item.get('canonical_url')
    out_item['item_guid_isPermaLink'] = item.get('guid').get('+@isPermaLink')
    out_item['item_guid'] = as_int(item.get('guid').get('+content'))
    out_item['item_creator'] = item.get('creator')
    out_item['item_primary_tag'] = item.get('primary_tag')
    out_item['item_category'] = item.get('category')
    out_item['item_categories'] = item.get('categories')
    out_item['item_tags'] = item.get('tags')
    out_item['item_content_url'] = content_url
    out_item['item_content_medium'] = content_medium
    out_item['item_title_type'] = title_type
    out_item['item_description_type'] = description_type
    out_item['item_thumbnail_url'] = thumb_url
    out_item['item_thumbnail_width'] = thumb_w
    out_item['item_thumbnail_height'] = thumb_h
    out_item['item_content_thumbnail'] = media_thumbs[1] if len(media_thumbs) > 1 else None
    out_item['item_description'] = item.get('description')
    out_item['item_excerpt'] = item.get('excerpt')
    out_item['item_pubDate'] = item.get('pubDate')
    out_item['item_updateDate'] = item.get('updateDate')
    out_item['item_primary_category'] = item.get('primary_category') or None
    out_item['item_youtube_id'] = item.get('youtube_id') or None

    out.append(out_item)

print(json.dumps(out))
