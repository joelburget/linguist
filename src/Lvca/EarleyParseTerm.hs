{-# LANGUAGE RecursiveDo     #-}
{-# LANGUAGE TemplateHaskell #-}
module Lvca.EarleyParseTerm (concreteParser) where

import           Control.Applicative  (many, (<|>))
import           Control.Lens         (ALens', ifor, ix, view, (<&>), (^?!))
import           Control.Lens.TH      (makeLenses)
import           Control.Monad.Fix
import           Control.Monad.Reader
import           Data.Char            (isSpace, isAlpha, isAlphaNum)
import           Data.Foldable        (asum)
import           Data.Map             (Map)
import qualified Data.Map             as Map
import           Data.Sequence        (Seq(Empty, (:|>), (:<|)))
import qualified Data.Sequence        as Seq
import           Data.Text            (Text)
import qualified Data.Text            as Text
import           Data.Void            (Void)
import           GHC.Stack            (HasCallStack)
import           Prelude              hiding ((!!))
import           Text.Earley
  (Grammar, Parser, Prod, parser, rule, satisfy, terminal, token, (<?>))

import           Lvca.TokenizeConcrete
import           Lvca.Types           hiding (space)

data Parsers r = Parsers
  -- { _whitespaceParser :: !(Prod r Text Char String)
  { _higherPrecParser :: !(Prod r Text ConcreteToken (Term Void))
  , _samePrecParser   :: !(Prod r Text ConcreteToken (Term Void))
  }
makeLenses ''Parsers

(!!) :: HasCallStack => Seq a -> Int -> a
as !! i = case Seq.lookup i as of
  Just a  -> a
  Nothing -> error "Invariant violation: sequence too short"

-- | Parse 'Text' to a 'Term' for some 'ConcreteSyntax'
concreteParser
  :: ConcreteSyntax -> Parser Text [ConcreteToken] (Term Void)
concreteParser concreteSyntax = parser (concreteParserGrammar concreteSyntax)

concreteParserGrammar
  :: forall r.
     ConcreteSyntax
  -> Grammar r (Prod r Text ConcreteToken (Term Void))
concreteParserGrammar (ConcreteSyntax directives) = mdo
  -- whitespace <- rule $ many $ satisfy isSpace

  it <- mfix $ \prods ->
    -- highest precedence to lowest
    ifor directives $ \precedence precedenceLevel -> do

      let opNames = _csOperatorName <$> precedenceLevel
          prodTag = Text.intercalate " | " opNames

          -- parsers for every operator sharing this precedence (note the
          -- knot-tying)
          samePrecP = prods !! precedence

          _ :|> lowestPrec = prods

          -- If this is the highest precedence level then we allow
          -- subexpressions of any precedence with parens, otherwise we allow
          -- (unparenthesized) subexpressions of higher precedence (which of
          -- course include parenthesized expressions)
          higherPrecP = if precedence == 0
            then parens lowestPrec
            else prods !! pred precedence

          thisLevelProds = precedenceLevel <&>
            \(ConcreteSyntaxRule opName slots directive) ->
              let parser' = case directive of
                    InfixDirective str fixity  -> parseInfix opName str fixity
                    MixfixDirective directive' -> do
                      prodMap <- parseMixfixDirective directive'

                      -- convert @Map Text (Scope Void)@ to @[Scope Void]@ by
                      -- order names appear in @slots@ (which is the order
                      -- they occur in on the lhs of the concrete parser spec)
                      let prodList = prodMap <&>
                            \(MixfixResult varNameMap subTmMap) ->
                              slots <&> \(binders, tmName) ->
                                let binders' = binders <&> \varName ->
                                      varNameMap ^?! ix varName
                                    body = subTmMap ^?! ix tmName
                                in Scope binders' body

                      pure $ Term opName <$> prodList
            in runReader parser' $ Parsers higherPrecP samePrecP

      --  parse any expression with this, or higher, precedence
      rule $ asum thisLevelProds
        <|> higherPrecP
        <?> prodTag

  case it of
    -- enter the lowest precedence parser
    _ :|> lowestPrecParser
      -> pure $ lowestPrecParser
    Empty
      -> error "no concrete parsing precedence levels found"

parens :: Prod r e ConcreteToken a -> Prod r e ConcreteToken a
parens p = token (LiteralToken "(") *> p <* token (LiteralToken ")")

data MixfixResult = MixfixResult
  !(Map Text Text)
  !(Map Text (Term Void))

instance Semigroup MixfixResult where
  MixfixResult a1 b1 <> MixfixResult a2 b2 = MixfixResult (a1 <> a2) (b1 <> b2)

instance Monoid MixfixResult where
  mempty = MixfixResult Map.empty Map.empty

parseMixfixDirective
  :: MixfixDirective
  -> Reader (Parsers r) (Prod r Text ConcreteToken MixfixResult)
parseMixfixDirective directive = do
  -- Parsers whitespace _ _ <- ask
  Parsers higherPrecParser _ <- ask

  let returnVar concreteGrammarName parsedName
        = MixfixResult (Map.singleton concreteGrammarName parsedName) Map.empty
      returnSubtm concreteGrammarName tm
        = MixfixResult Map.empty (Map.singleton concreteGrammarName tm)

  case directive of
    Literal text -> pure $ mempty <$ token (LiteralToken text) -- <* whitespace
    Sequence d1 d2 -> do
      d1' <- parseMixfixDirective d1
      d2' <- parseMixfixDirective d2
      pure $ (<>) <$> d1' <*> d2'
    Line              -> pure $ mempty <$ token Newline -- <* whitespace
    Nest _ directive' -> parseMixfixDirective directive'
    Group  directive' -> parseMixfixDirective directive'
    d1 :<+ d2 -> do
      d1' <- parseMixfixDirective d1
      d2' <- parseMixfixDirective d2
      pure $ d1' <|> d2'
    VarName concreteGrammarName -> pure $
      fmap (returnVar concreteGrammarName) parseVar
    SubTerm name -> pure $
      fmap (returnSubtm name) higherPrecParser <|>
      fmap (returnVar name) parseVar

parseVar :: Prod r Text ConcreteToken Text
parseVar = terminal $ \case
  VarToken v -> Just v
  _          -> Nothing

--   let char0 = satisfy $ \c ->
--            isAlpha c
--         || c == '_'
--       chars = many $ satisfy $ \c ->
--            isAlphaNum c
--         || c == '\''
--         || c == '_'
--   in Text.pack <$> ((:) <$> char0 <*> chars)

-- | Parse an infix operator
parseInfix
  :: Text -- ^ Operator name (in abstract syntax), eg @"Add"@
  -> Text -- ^ Operator representation (in concrete syntax), eg @"+"@
  -> Fixity
  -> Reader (Parsers r) (Prod r Text ConcreteToken (Term Void))
parseInfix opName opRepr fixity
  = reader $ \(Parsers higherPrec samePrec) ->
    -- Allow expressions of the same precedence on the side we're associative
    -- on
    let (subparser1, subparser2) = case fixity of
          Infixl -> (samePrec  , higherPrec)
          Infix  -> (higherPrec, higherPrec)
          Infixr -> (higherPrec, samePrec  )
    in BinaryTerm opName
         <$> subparser1
         -- <*  whitespace
         <*  token (LiteralToken opRepr)
         -- <*  whitespace
         <*> subparser2

_unused :: ALens' (Parsers r) (Prod r Text ConcreteToken (Term Void))
_unused = samePrecParser
