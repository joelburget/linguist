module Lvca.ParseSyntaxDescription where

import           Control.Lens                  (unsnoc)
import           Data.Foldable                 (asum)
import qualified Data.Map                      as Map
import           Data.Text                     (Text)
import           Data.Void                     (Void)
import           Text.Megaparsec
import qualified Text.Megaparsec.Char.Lexer    as L

import           Lvca.ParseUtil
import           Lvca.Types
import           Text.Megaparsec.Char.LexerAlt (indentBlock)


type SyntaxDescriptionParser a = Parsec
  Void -- error type
  Text -- stream type
  a

parseSyntaxDescription :: SyntaxDescriptionParser SyntaxChart
parseSyntaxDescription
  = SyntaxChart . Map.fromList <$> some parseSortDef <* eof

-- | Parse a sort definition, eg:
--
-- @
-- Foo ::=
--   Bar
--   Baz
-- @
parseSortDef :: SyntaxDescriptionParser (SortName, SortDef)
parseSortDef = L.nonIndented scn $ indentBlock scn $ do
  name      <- parseName
  variables <- many parseName
  _         <- symbol "::="

  asum
    -- Try to parse the multiline version, eg:
    --
    -- @
    -- Foo ::=
    --   Bar
    --   Baz
    -- @
    [ pure $ L.IndentMany Nothing (pure . (name,) . (SortDef variables))
        parseOperator

    -- TODO:
    -- Failing that, try the single line version:
    --
    -- @
    -- Foo ::= Bar | Baz
    -- @
    -- , L.IndentNone . (name,) . SortDef variables <$>
    --     parseOperator `sepBy1` symbol "|"
    ]

-- | Parse an operator.
--
-- The first two cases are sugar so you can write:
--
--   - @{Num}@ instead of
--   - @Num{Num}@ instead of
--   - @Num({Num})@.
parseOperator :: SyntaxDescriptionParser Operator
parseOperator = asum
  [ do -- sugar for `{Num}`
       name <- braces parseName
       Operator name (ExternalArity name) <$> option "" stringLiteral
  , do
       name <- parseName
       asum
         [ -- sugar for `Num{Num}`
           Operator name
           <$> braces (ExternalArity <$> parseName)
           <*> option "" stringLiteral
           -- unsweetened
         , Operator name
           <$> parseArity
           <*> option "" stringLiteral
         ]
  ]

-- | Parse an arity, which is a list of valences separated by @;@, eg:
--
-- @
-- A; B; C
-- A. B. C
-- A. B. F A B
-- A. B; C
-- A
-- {External}
-- {External}; A
-- {External}. A
-- A. {External}
-- @
parseArity :: SyntaxDescriptionParser Arity
parseArity = fmap Arity $ option [] $
  parens $ option [] $ parseValence `sepBy1` symbol ";"

-- | Parse a valence, which is a list of sorts separated by @.@, eg any of:
--
-- @
-- A. B. C
-- A. B. F A B
-- A
-- {External}
-- {External}. A
-- A. {External}
-- @
parseValence :: SyntaxDescriptionParser Valence
parseValence = do
  names <- parseSort `sepBy1` symbol "."
  let Just (sorts, result) = unsnoc names
  pure $ Valence sorts result

-- | Parse a sort, which is a regular sort name or an external sort name in
-- braces, eg any of:
--
-- @
-- A
-- F A B
-- {External}
-- @
parseSort :: SyntaxDescriptionParser Sort
parseSort = asum
  [ braces $ External <$> parseName
  , SortAp
      <$> parseName
      <*> many (asum
        [ SortAp <$> parseName <*> pure []
        , parens parseSort
        ])
  ]
