{-# LANGUAGE TemplateHaskell #-}

import           EasyTest

import qualified Languages.Arith         as Arith
import qualified Languages.Document      as Document
import qualified Languages.SimpleExample as SimpleExample
import qualified Languages.Stlc          as Stlc
-- import           Languages.TExample      ()
import qualified Test.Bidirectional as BD
import           Test.Core
import           Test.ParseBidirectional
import           Test.ParseConcreteSyntaxDescription
import           Test.ParseLanguage

-- import Test.Inspection
import           Test.Types

main :: IO ()
main = cabalTestSuite $ run allTests

allTests :: Test
allTests = scope "all tests" $ tests
  [ scope "toPattern"              toPatternTests
  , scope "stlc"                   Stlc.stlcTests
  , scope "matches"                SimpleExample.matchesTests
  , scope "minus"                  SimpleExample.minusTests
  , scope "completePatternTests"   SimpleExample.completePatternTests
  , scope "simple-example"         SimpleExample.dynamicTests
  , scope "pretty-syntax"          SimpleExample.prettySyntaxChartTests
  , scope "syntax-statics"         SimpleExample.prettyStaticTests
  -- , scope "simple-example.eval"    SimpleExample.evalTests
  , scope "simple-example.parse"   SimpleExample.parseTests
  , scope "simple-example.props"   SimpleExample.propTests
  -- , scope "t-example.eval"         TExample.evalTests
  , scope "document"               Document.documentTests
  -- , scope "arith"                  Arith.arithTests
  , scope "bidirectional"          BD.checkingTests
  , scope "bidirectional.parse"    testParseBidirectional
  , scope "concrete.parse"         parseTests
  , scope "core"                   coreEvalTests
  ]

-- inspect $ 'SimpleExample.patP === 'SimpleExample.explicitPatP
