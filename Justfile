build:
    swift build

test:
    swift test

bundle *flags:
    scripts/bundle.sh {{flags}}

run: bundle
    open build/dinky.app

vm-install: bundle
    scripts/vm-install.sh

# Symlink the bundled CLI into ~/.local/bin so `dinky <command>` works from any shell.
install: bundle
    mkdir -p ~/.local/bin
    ln -sf "$PWD/build/dinky.app/Contents/MacOS/dinky" ~/.local/bin/dinky
    ls -l ~/.local/bin/dinky
