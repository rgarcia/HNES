HNES_CSS = ./stylesheets/style.css
HNES_LESS = ./stylesheets/style.less
DATE=$(shell date +%I:%M%p)
CHECK=\033[32m✔\033[39m
HR=\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#\#

build:
	@echo "\n${HR}"
	@echo "Building HNES..."
	@echo "${HR}\n"
	@coffeelint -f coffeelint.json javascripts/*.coffee
	@echo "Running CoffeeLint...                       ${CHECK} Done"
	@coffee -c javascripts/
	@echo "Compiling coffeescript...                   ${CHECK} Done"
	@recess --compile ${HNES_LESS} > ${HNES_CSS}
	@echo "Compiling LESS with Recess...               ${CHECK} Done"
	@echo "HNES successfully built at ${DATE}."

watch:
	@echo "Watching less and coffee files..."; \
	watchr -e "watch('javascripts/.*\.coffee') { system 'make' }; watch('stylesheets/.*\.less') { system 'make' }"
