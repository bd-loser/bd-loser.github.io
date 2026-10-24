# bd-loser.github.io

Landing page for the Android/Termux tooling (featured: [opencode-bionic](https://github.com/bd-loser/opencode-bionic), [bun-termux](https://github.com/bd-loser/bun-termux)).

Single static page. Built at deploy time: screenshots + badges are fetched same-origin, versions are read live from the repos' tags (fallback: `versions.env`).

Local build: `bash src/build.sh` -> `public/index.html`.
