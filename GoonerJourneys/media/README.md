# Addon images

Images the addon shows in game (Hall of Fame photos). WoW addons can only
display `.tga` or `.blp` files whose width and height are powers of two
(e.g. 512x256). Make one from a screenshot with:

```bash
python scripts/make_photo.py screenshot.jpg GoonerJourneys/media/hall_of_thanes.tga
```

Only `.tga` and `.blp` files from this folder go into the release zip.
