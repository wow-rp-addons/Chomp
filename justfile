packager_url := "https://raw.githubusercontent.com/BigWigsMods/packager/v2/release.sh"

default: check test

check:
	luacheck -q $(git ls-files '*.lua')

test:
	busted  '--lpath=Tests/?.lua' Tests/*Spec.lua

dist:
	curl -s {{ packager_url }} | bash -s -- -dl

libs:
	curl -s {{ packager_url }} | bash -s -- -cdlz
	cp -a .release/Chomp/Libs/* Libs/
