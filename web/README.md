# Shadow Arena - web build

This folder is the exported browser version of the game (Godot 4.7 web
export, single-threaded, Compatibility renderer) and is what Vercel
serves. Do not edit these files by hand; re-export instead:

    godot --headless --path Game --export-release "Web" ../web/index.html

`vercel.json` only sets cache headers. No special COOP/COEP headers are
needed because the build does not use threads.
