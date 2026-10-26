.PHONY: help setup start stop restart down logs status update build shell backup

help:
	@./enshrouded help
setup:
	@./enshrouded setup
start:
	@./enshrouded start
stop:
	@./enshrouded stop
restart:
	@./enshrouded restart
down:
	@./enshrouded down
logs:
	@./enshrouded logs
status:
	@./enshrouded status
update:
	@./enshrouded update
build:
	@./enshrouded build
shell:
	@./enshrouded shell
backup:
	@./enshrouded backup
