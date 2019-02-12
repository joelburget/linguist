repl:
	cabal new-repl lvca:exe:lvca

test-repl:
	cabal new-repl lvca:test:tests

test:
	cabal new-test

g:
	ghcid --command="cabal new-repl lvca:exe:lvca"

style:
	stylish-haskell -i $(shell find src test -name "*.hs" -not -name "TH.hs")
