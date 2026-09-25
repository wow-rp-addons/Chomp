PACKAGER_URL := "https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh"

default: check test

check:
	luacheck -q $(git ls-files '*.lua')

test:
	busted  '--lpath=Tests/?.lua' Tests/*Spec.lua

dist:
	curl -s {{PACKAGER_URL}} | bash -s -- -d -l -S

libs:
	curl -s {{PACKAGER_URL}} | bash -s -- -c -d -z
	cp -a .release/Chomp/Libs/* Libs/
