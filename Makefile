ifeq ($(CIRCLECI),true)
  ifneq ($(CIRCLE_PULL_REQUEST),)
    CIRCLE_PR_NUMBER ?= $(shell echo ${CIRCLE_PULL_REQUEST##*/})
  endif
  REPO := $(CIRCLE_PROJECT_USERNAME)/$(CIRCLE_PROJECT_REPONAME)
  BRANCH := $(CIRCLE_BRANCH)
  PR_NUMBER=$(if $(CIRCLE_PR_NUMBER),$(CIRCLE_PR_NUMBER),false)
  BUILD_NUMBER := $(CIRCLE_BUILD_NUM)
  GIT_COMMIT := $(CIRCLE_SHA1)
  GIT_TAG := $(CIRCLE_TAG)
else ifeq ($(TRAVIS),true)
  REPO := $(TRAVIS_REPO_SLUG)
  BRANCH := $(if $(TRAVIS_PULL_REQUEST_BRANCH),$(TRAVIS_PULL_REQUEST_BRANCH),$(TRAVIS_BRANCH))
  PR_NUMBER := $(TRAVIS_PULL_REQUEST)
  BUILD_NUMBER := $(TRAVIS_BUILD_NUMBER)
  GIT_COMMIT := $(if $(TRAVIS_PULL_REQUEST_SHA),$(TRAVIS_PULL_REQUEST_SHA),$(TRAVIS_COMMIT))
  GIT_TAG := $(TRAVIS_TAG)
  COMMIT_MESSAGE := $(TRAVIS_COMMIT_MESSAGE)
else ifeq ($(TF_BUILD),True)
  REPO := $(BUILD_REPOSITORY_NAME)
  BRANCH := $(if $(SYSTEM_PULLREQUEST_SOURCEBRANCH),$(SYSTEM_PULLREQUEST_SOURCEBRANCH),$(BUILD_SOURCEBRANCHNAME))
  PR_NUMBER := $(if $(SYSTEM_PULLREQUEST_PULLREQUESTNUMBER),$(SYSTEM_PULLREQUEST_PULLREQUESTNUMBER),false)
  BUILD_NUMBER := $(BUILD_BUILDNUMBER)
  GIT_COMMIT := $(shell git rev-parse --verify "HEAD^2" 2>/dev/null)
  ifeq ($(GIT_COMMIT),)
    GIT_COMMIT ?= $(BUILD_SOURCEVERSION)
  endif
else
  REPO := $(subst https://github.com/,,$(CHANGE_URL))
  ifneq ($(CHANGE_ID),)
    REPO := $(subst /pull/$(CHANGE_ID),,$(REPO))
  endif
  PR_NUMBER := $(CHANGE_ID)
  BRANCH := $(BRANCH_NAME)
endif
$(info REPO=$(REPO))
$(info PR_NUMBER=$(PR_NUMBER))
$(info BRANCH=$(BRANCH))
$(info BUILD_NUMBER=$(BUILD_NUMBER))

ifeq ($(GIT_COMMIT),)
  GIT_COMMIT := $(shell git log --format="%H" -n 1)
  GIT_REF := $(shell git log --format="%h" -n 1)
else
  GIT_COMMIT := $(shell git rev-parse ${GIT_COMMIT})
  GIT_REF := $(shell git rev-parse --short ${GIT_COMMIT})
endif
$(info GIT_COMMIT=$(GIT_COMMIT))
ifeq ($(GIT_TAG),)
  GIT_TAG := $(shell git describe --abbrev=0 --tags --exact-match ${GIT_COMMIT} 2>/dev/null)
endif
$(info GIT_TAG=$(GIT_TAG))
ifeq ($(COMMIT_MESSAGE),)
  COMMIT_MESSAGE := $(shell git log --format="%s" -n 1 ${GIT_COMMIT})
endif
$(info COMMIT_MESSAGE=$(COMMIT_MESSAGE))

BUILD := $(GIT_TAG)
ifeq ($(BUILD),)
  ifeq ($(BRANCH),)
    # If we are not on CI or it's not a TAG build, we add "-dev" to the name
    BUILD := $(GIT_REF)$(shell if ! $$(git describe --abbrev=0 --tags --exact-match ${GIT_COMMIT} 2>/dev/null >/dev/null); then echo "-dev"; fi)
  else
    BUILD := $(BRANCH)
  endif
endif

DESTDIR := monica-$(BUILD)
ASSETS := monica-assets-$(BUILD)
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

default: build

all:
	$(MAKE) fullclean
	$(MAKE) build
	$(MAKE) dist

build:
	composer install --no-interaction --ignore-platform-reqs
	php artisan lang:generate
	yarn inst
	yarn lint --fix
	yarn run production

build-prod:
	composer install --no-interaction --ignore-platform-reqs --no-dev
	php artisan lang:generate
	yarn inst
	yarn lint --fix
	yarn run production

build-dev:
	composer install --no-interaction --ignore-platform-reqs
	php artisan lang:generate
	yarn inst
	yarn lint --fix
	yarn run dev

prepare: $(DESTDIR) $(ASSETS)
	mkdir -p results

$(DESTDIR):
	mkdir -p $@
	ln -s ../readme.md $@/
	ln -s ../CONTRIBUTING.md $@/
	ln -s ../CHANGELOG.md $@/
	ln -s ../CONTRIBUTORS $@/
	ln -s ../LICENSE $@/
	ln -s ../.env.example $@/
	ln -s ../composer.json $@/
	ln -s ../composer.lock $@/
	ln -s ../package.json $@/
	ln -s ../yarn.lock $@/
	ln -s ../app.json $@/
	ln -s ../nginx_app.conf $@/
	ln -s ../server.php $@/
	ln -s ../webpack.mix.js $@/
	ln -s ../Procfile $@/
	ln -s ../app $@/
	ln -s ../artisan $@/
	ln -s ../bootstrap $@/
	ln -s ../config $@/
	ln -s ../database $@/
	ln -s ../docs $@/
	ln -s ../public $@/
	ln -s ../resources $@/
	ln -s ../routes $@/
	ln -s ../vendor $@/
	mkdir -p $@/storage/app/public
	mkdir -p $@/storage/debugbar
	mkdir -p $@/storage/logs
	mkdir -p $@/storage/framework/views
	mkdir -p $@/storage/framework/cache
	mkdir -p $@/storage/framework/sessions
	echo "$(GIT_REF)" > $@/.sentry-release
	echo "$(GIT_COMMIT)" > $@/.sentry-commit

$(ASSETS):
	mkdir -p $@/public
	ln -s ../../public/mix-manifest.json $@/public/
	ln -s ../../public/js $@/public/
	ln -s ../../public/css $@/public/
	ln -s ../../public/fonts $@/public/

dist: results/$(DESTDIR).tar.bz2 results/$(ASSETS).tar.bz2

assets: results/$(ASSETS).tar.bz2

DESCRIPTION := $(shell echo "$(COMMIT_MESSAGE)" | sed -s 's/"/\\\\\\\\\\"/g' | sed -s 's/(/\\(/g' | sed -s 's/)/\\)/g' | sed -s 's%/%\\/%g')

ifeq (,$(DEPLOY_TEMPLATE))
DEPLOY_TEMPLATE := scripts/ci/.deploy.json.in
endif

.deploy.json: $(DEPLOY_TEMPLATE)
	cp $< $@
	sed -si "s/\$$(version)/$(BUILD)/" $@
	sed -si "s/\$$(description)/$(DESCRIPTION)/" $@
	sed -si "s/\$$(released)/$(shell date -u '+%FT%T.000Z')/" $@
	sed -si "s/\$$(vcs_tag)/$(GIT_TAG)/" $@
	sed -si "s/\$$(vcs_commit)/$(GIT_COMMIT)/" $@
	sed -si "s/\$$(build_number)/$(BUILD_NUMBER)/" $@

results/%.tar.xz: % prepare
	tar chfJ $@ --exclude .gitignore --exclude .gitkeep $<

results/%.tar.bz2: % prepare
	tar chfj $@ --exclude .gitignore --exclude .gitkeep $<

results/%.tar.gz: % prepare
	tar chfz $@ --exclude .gitignore --exclude .gitkeep $<

results/%.zip: % prepare
	zip -rq9 $@ $< --exclude "*.gitignore*" "*.gitkeep*"

clean:
	rm -rf $(DESTDIR) $(ASSETS)
	rm -f results/$(DESTDIR).* results/$(ASSETS).* .deploy.json

fullclean: clean
	rm -rf vendor resources/vendor public/fonts/vendor node_modules
	rm -f public/css/* public/js/* public/mix-manifest.json public/storage bootstrap/cache/*

install: .env build-dev
	php artisan key:generate
	php artisan setup:test
	php artisan passport:install

update: .env build-dev
	php artisan migrate

.env:
	cp .env.example .env

.PHONY: dist clean fullclean install update build prepare build-prod build-dev

vagrant_build:
	make -C scripts/vagrant/build package
