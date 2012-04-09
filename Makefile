.PHONY : test

PATH := ./node_modules/.bin/:$(PATH)
LIBS = $(subst src,lib,$(subst coffee,js,$(wildcard ./src/*.coffee)))
HEAD = $(shell git describe --contains --all HEAD)
REPORTER ?= dot

all : server.js $(LIBS)

lib/%.js : src/%.coffee
	@mkdir -p lib
	@coffee -pbc $< > $@

%.js : %.coffee
	@coffee -pbc $< > $@

test : all
	@mocha --compilers coffee:coffee-script --reporter $(REPORTER)

clean :
	@rm *.js lib/*.js || true
