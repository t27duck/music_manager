# All builds run inside containers so the host needs only Docker.
UID := $(shell id -u)
GID := $(shell id -g)
CACHE ?= $(HOME)/.cache/music-manager-build
DIST := dist

UBUNTU_IMAGE := music-manager-ubuntu
ARCH_IMAGE := music-manager-arch

DOCKER_UBUNTU = docker run --rm -u $(UID):$(GID) -e HOME=/tmp/home \
	-v $(CURDIR):/src -v $(CACHE)/cargo:/usr/local/cargo/registry \
	-v $(CACHE)/npm:/tmp/home/.npm $(UBUNTU_IMAGE)

.PHONY: help images image-ubuntu image-arch deps check test lint deb arch package clean

help:
	@echo "make images   - build the Ubuntu and Arch build containers"
	@echo "make check    - cargo check + svelte-check (Ubuntu container)"
	@echo "make test     - run Rust unit tests (Ubuntu container)"
	@echo "make deb      - build the .deb into $(DIST)/"
	@echo "make arch     - build the Arch .pkg.tar.zst into $(DIST)/"
	@echo "make package  - build both packages"

images: image-ubuntu image-arch

image-ubuntu:
	docker build -t $(UBUNTU_IMAGE) -f docker/Dockerfile.ubuntu docker

image-arch:
	docker build -t $(ARCH_IMAGE) -f docker/Dockerfile.arch docker

$(CACHE):
	mkdir -p $(CACHE)/cargo $(CACHE)/npm

deps: | $(CACHE)
	$(DOCKER_UBUNTU) npm ci

check: deps
	$(DOCKER_UBUNTU) sh -c "npm run check && cd src-tauri && cargo check --all-targets && cargo clippy --all-targets -- -D warnings && cargo fmt --check"

test: | $(CACHE)
	$(DOCKER_UBUNTU) sh -c "cd src-tauri && cargo test"

deb: deps
	$(DOCKER_UBUNTU) npm run tauri build -- --bundles deb
	mkdir -p $(DIST)
	cp src-tauri/target/release/bundle/deb/*.deb $(DIST)/

arch: | $(CACHE)
	mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=music-manager/ -o $(DIST)/music-manager-src.tar.gz HEAD
	docker run --rm -v $(CURDIR)/packaging/arch/PKGBUILD:/in/PKGBUILD:ro \
		-v $(CURDIR)/$(DIST):/out $(ARCH_IMAGE) sh -c '\
		cp /in/PKGBUILD /out/music-manager-src.tar.gz . && \
		makepkg -f --noconfirm && \
		sudo cp *.pkg.tar.zst /out/ && sudo chown $(UID):$(GID) /out/*.pkg.tar.zst'
	rm -f $(DIST)/music-manager-src.tar.gz

package: deb arch

clean:
	rm -rf $(DIST) build node_modules src-tauri/target
