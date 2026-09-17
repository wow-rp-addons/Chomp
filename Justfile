PACKAGER_URL := "https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh"
LUA := env_var_or_default("LUA", "lua5.1")

default: check

check:
	luacheck -q $(git ls-files '*.lua')

test:
	exec "{{LUA}}" "$(luarocks --lua-version=5.1 show busted --rock-dir)/bin/busted" '--lpath=Tests/?.lua' Tests/ChompSpec.lua

dist:
	curl -s {{PACKAGER_URL}} | bash -s -- -d -l -S

libs:
	curl -s {{PACKAGER_URL}} | bash -s -- -c -d -z
	cp -a .release/Chomp/Libs/* Libs/
