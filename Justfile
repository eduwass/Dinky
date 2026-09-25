build:
    swift build

test:
    swift test

bundle *flags:
    scripts/bundle.sh {{flags}}

# Debug bundle, replace any running dinky, and run attached so logs stream here (fut's run extension uses this).
run: kill
    scripts/bundle.sh --debug
    ./build/dinky.app/Contents/MacOS/dinky

kill:
    pkill -f "dinky.app/Contents/MacOS/dinky" || true

vm-install: bundle
    scripts/vm-install.sh

# Symlink the bundled CLI into ~/.local/bin so `dinky <command>` works from any shell.
install: bundle
    mkdir -p ~/.local/bin
    ln -sf "$PWD/build/dinky.app/Contents/MacOS/dinky" ~/.local/bin/dinky
    ls -l ~/.local/bin/dinky
