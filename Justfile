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
