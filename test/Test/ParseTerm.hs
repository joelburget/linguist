module Test.ParseTerm where

import Control.Monad.Reader
import           Data.Text.Prettyprint.Doc             (defaultLayoutOptions,
                                                        layoutPretty, Pretty(pretty))
import           Data.Text.Prettyprint.Doc.Render.Text (renderStrict)
import           EasyTest             (Test, expectEq)
import           Hedgehog             hiding (Test, Var)
import Data.Text (Text, unpack)
import           Text.Megaparsec (parseMaybe, runParser, errorBundlePretty)

import Lvca.Types
import Lvca.ParseTerm
import Test.Types

prop_parse_pretty
  :: (Show a, Pretty a, Eq a)
  => SyntaxChart
  -> Sort
  -> (SortName -> Maybe (Gen a))
  -> ExternalParsers a
  -> Property
prop_parse_pretty chart sort aGen aParsers = property $ do
  tm <- forAll $ genTerm chart sort aGen
    -- (Just (Gen.int Range.exponentialBounded))

  let pretty' = renderStrict . layoutPretty defaultLayoutOptions . pretty
      parse'  = parseMaybe $ runReaderT standardParser $
        ParseEnv chart sort TaggedExternals aParsers

  annotate $ unpack $ pretty' tm
  parse' (pretty' tm) === Just tm

standardParseTermTest
  :: (Eq a, Show a)
  => ParseEnv a -> Text -> Term a -> Test ()
standardParseTermTest env str tm =
  case runParser (runReaderT standardParser env) "(test)" str of
    Left err       -> fail $ errorBundlePretty err
    Right parsedTm -> expectEq parsedTm tm
