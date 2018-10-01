module Main where

import           Brick
import           Control.Lens
import           Control.Monad.Reader
import           Control.Zipper
import           EasyTest

import           Linguist.Brick
import           Linguist.Proceed ()
import           Linguist.Types
import           Linguist.Util (forceRight)

import qualified Linguist.Languages.Arith         as Arith
import qualified Linguist.Languages.Document      as Document
import           Linguist.Languages.MachineModel
import qualified Linguist.Languages.SimpleExample as SimpleExample
import qualified Linguist.Languages.Stlc          as Stlc
import qualified Linguist.Languages.TExample      as TExample


natJudgement :: JudgementForm
natJudgement = JudgementForm "nat" [(JIn, "a")]

natJudgements :: JudgementRules
natJudgements = JudgementRules
  [ []
    .--
    ["zero"] %%% "nat"
  , [["a"] %%% "nat"]
    .--
    ["succ" @@ ["a"]] %%% "nat"
  ]

--

main :: IO ()
main = do
  _ <- defaultMain app $
    -- let env = (SimpleExample.syntax, SimpleExample.dynamics)
    --     steps :: [StateStep SimpleExample.E]
    --     steps = iterate (\tm -> runReader (proceed tm) env) $
    --       StateStep [] (Descending SimpleExample.tm1)
    let env = (forceRight Arith.syntax, forceRight Arith.machineDynamics, const Nothing)
        steps :: [StateStep Int]
        steps = iterate (\tm -> runReader (error "TODO" tm) env) $
          StateStep [] (Descending Arith.tm)
    in State (zipper steps & fromWithin traverse) False
  pure ()

allTests :: Test ()
allTests = scope "all tests" $ tests
  [ "toPattern"              toPatternTests
  , "stlc"                   Stlc.stlcTests
  , "matches"                SimpleExample.matchesTests
  , "minus"                  SimpleExample.minusTests
  , "completePatternTests"   SimpleExample.completePatternTests
  , "simple-example"         SimpleExample.dynamicTests
  , "pretty-syntax"          SimpleExample.prettySyntaxChartTests
  , "syntax-statics"         SimpleExample.prettyStaticTests
  , "simple-example.eval"    SimpleExample.evalTests
  , "t-example.eval"         TExample.evalTests
  , "document"               Document.documentTests
  , "arith"                  Arith.evalTests
  ]

-- main :: IO ()
-- main = do
--   putStrLn "syntax:\n"
--   putDoc (pretty eChart)
--   putStrLn "\n"
--   putStrLn "judgements:\n"
--   putDoc (pretty natJudgements)
--   putStrLn "\n"
