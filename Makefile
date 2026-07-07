.PHONY: core-build core-test core-run core-capture zip clean

core-build:
	cd core && dune build

core-test:
	cd core && dune runtest

core-run:
	./scripts/run-core.sh

core-capture:
	cd core && PHAROS_DB=../var/pharos.dev.sqlite dune exec pharos -- capture "Manual starter request from Makefile"

zip:
	cd .. && zip -r pharos-starter.zip pharos-starter -x "*/_build/*" "*/.build/*" "*/.swiftpm/*" "*/var/*.sqlite*"

clean:
	rm -rf core/_build ui/macos/PharosApp/.build ui/macos/PharosApp/.swiftpm
