#!/usr/bin/make -f

override CURRENT_MAKEFILE_DIR := $(realpath $(dir $(firstword $(MAKEFILE_LIST))))
override TOP_LEVEL := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))

-include .settings.mk

export DOCKER_UID := $(shell id -u)
export DOCKER_GID := $(shell id -g)
export DOCKER_GIDS := $(shell id -G)

docker_run = docker run --rm $(docker_run_options)
docker_compose_run = docker-compose $(docker_compose_files) run --rm
docker_run_options = \
	     -e http_proxy -e DOCKER_UID -e DOCKER_GID -e DOCKER_GIDS \
	     --entrypoint /root/entrypoint.sh -v $(TOP_LEVEL)/bin/entrypoint.sh:/root/entrypoint.sh:ro \

clean:
build:
pull:
prune:

.PHONY: clean build pull
