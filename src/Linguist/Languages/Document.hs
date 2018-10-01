{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE TemplateHaskell     #-}
module Linguist.Languages.Document where

import qualified CMark                              as MD
import qualified CMark.Patterns                     as MD
import           Control.Lens
import           Data.Diverse
import           Data.Text                          (Text)
import           Data.Void                          (Void, absurd)
import           EasyTest
import           NeatInterpolation
import           Text.Megaparsec                    (ParseErrorBundle, runParser)

import           Linguist.Languages.Document.Syntax
import           Linguist.ParseSyntaxDescription
import           Linguist.Types                     (SyntaxChart, Term (..))

-- import qualified Data.Map as Map
-- import           Linguist.TH
-- import Language.Haskell.TH (lookupTypeName, Type(..), mkName)

data InlineEmbed

newtype Document blockEmbed inlineEmbed = Document [Block blockEmbed inlineEmbed]

data Block blockEmbed inlineEmbed
  = Header !HeaderLevel !Text
  | Paragraph !(Inline inlineEmbed)
  | BlockEmbed !blockEmbed

data HeaderLevel = H1 | H2 | H3

newtype Inline inlineEmbed = Inline [InlineAtom inlineEmbed]

data InlineAtom inlineEmbed
  = InlineAtom !(Maybe Attribute) !Text
  | InlineEmbed !inlineEmbed

data Attribute = Bold | Italic

syntax :: Either (ParseErrorBundle Text Void) SyntaxChart
syntax = runParser parseSyntaxDescription "(document syntax)" syntaxText

-- $(do
--   Just t <- lookupTypeName "Text"
--   mkTypes syntaxText $ Map.fromList
--     [ ("BlockEmbed",  VarT $ mkName "blockEmbed")
--     , ("InlineEmbed", VarT $ mkName "inlineEmbed")
--     , ("Text",        PromotedT t)
--     ])

type Term' a b = Term (Which '[a, b, Text])

model :: Prism' (Term' a b) (Document a b)
model = prism' bwd fwd where

  bwd = \case
    Document blocks -> Term "Document" [review (listP blockP) blocks]

  fwd = \case
    Term "Document" [blockList]
      -> Document <$> preview (listP blockP) blockList
    _ -> Nothing

maybeP :: Prism' (Term b) a -> Prism' (Term b) (Maybe a)
maybeP p = prism' bwd fwd where

  bwd = \case
    Nothing -> Term "Nothing" []
    Just x  -> Term "Just" [review p x]

  fwd = \case
    Term "Nothing" [] -> Just Nothing
    Term "Just" [x]   -> Just <$> preview p x
    _                 -> Nothing

listP :: Prism' (Term b) a -> Prism' (Term b) [a]
listP p = prism' bwd fwd where

  bwd = \case
    []   -> Term "Nil" []
    x:xs -> Term "Cons" [review p x, bwd xs]

  fwd = \case
    Term "Nil" []       -> Just []
    Term "Cons" [x, xs] -> (:) <$> preview p x <*> fwd xs
    _                   -> Nothing

blockP :: Prism' (Term' a b) (Block a b)
blockP = prism' bwd fwd where

  fwd = \case
    Term "Header" [level, PrimValue val] -> Header
      <$> preview headerLevelP level
      <*> trialN' @2 val
    Term "Paragraph" [inline] -> Paragraph <$> preview inlineP inline
    Term "BlockEmbed" [PrimValue val] -> BlockEmbed <$> trialN' @0 val
    _ -> Nothing

  bwd = \case
    Header level t -> Term "Header"
      [ (review headerLevelP) level
      , PrimValue (pickN @2 t)
      ]
    Paragraph inline -> Term "Paragraph" [review inlineP inline]
    BlockEmbed embed -> Term "BlockEmbed" [PrimValue (pickN @0 embed)]

headerLevelP :: Prism' (Term x) HeaderLevel
headerLevelP = prism' bwd fwd where

  bwd h =
    let h' = case h of
          H1 -> "H1"
          H2 -> "H2"
          H3 -> "H3"
    in Term h' []

  fwd = \case
    Term h [] -> case h of
      "H1" -> Just H1
      "H2" -> Just H2
      "H3" -> Just H3
      _    -> Nothing
    _ -> Nothing

inlineP :: Prism' (Term' a b) (Inline b)
inlineP = prism' bwd fwd where

  bwd (Inline inlines)
    = Term "Inline" [review (listP inlineAtomP) inlines]

  fwd = \case
    Term "Inline" [atoms] -> Inline <$> preview (listP inlineAtomP) atoms
    _                     -> Nothing

inlineAtomP :: Prism' (Term' a b) (InlineAtom b)
inlineAtomP = prism' bwd fwd where

  bwd :: InlineAtom b -> Term' a b
  bwd = \case
    InlineAtom attrs t -> Term "InlineAtom"
      [ review (maybeP attributeP) attrs
      , PrimValue (pickN @2 t)
      ]
    InlineEmbed embed -> Term "InlineEmbed" [PrimValue (pickN @1 embed)]

  fwd = \case
    Term "InlineAtom" [attrs, PrimValue val] -> InlineAtom
      <$> preview (maybeP attributeP) attrs
      <*> trialN' @2 val
    Term "InlineEmbed" [PrimValue val] -> InlineEmbed <$> trialN' @1 val
    _ -> Nothing

attributeP :: Prism' (Term x) Attribute
attributeP = prism' bwd fwd where

  bwd attr =
    let attr' = case attr of
          Bold   -> "Bold"
          Italic -> "Italic"
    in Term attr' []

  fwd = \case
    Term attr [] -> case attr of
      "Bold"   -> Just Bold
      "Italic" -> Just Italic
      _        -> Nothing
    _ -> Nothing

inlineAtomMdP :: forall b. Prism' MD.Node b -> Prism' MD.Node (InlineAtom b)
inlineAtomMdP embedP = prism' bwd fwd where

  bwd = \case
    InlineAtom Nothing t       -> MD.Text_ t
    InlineAtom (Just Bold) t   -> MD.Strong_ [MD.Text_ t]
    InlineAtom (Just Italic) t -> MD.Emph_ [MD.Text_ t]
    InlineEmbed b              -> review embedP b

  fwd = \case
   MD.Text_ t              -> Just $ InlineAtom Nothing t
   MD.Strong_ [MD.Text_ t] -> Just $ InlineAtom (Just Bold) t
   MD.Emph_ [MD.Text_ t]   -> Just $ InlineAtom (Just Italic) t
   _                       -> Nothing

blockMdP
  :: forall inlineEmbed blockEmbed.
     Prism' MD.Node blockEmbed
  -> Prism' MD.Node inlineEmbed
  -> Prism' MD.Node (Block blockEmbed inlineEmbed)
blockMdP blockEmbedP inlineEmbedP = prism' bwd fwd where

  bwd = \case
    Header h t ->
      let h' = case h of
            H1 -> 1
            H2 -> 2
            H3 -> 3
      in MD.Heading_ h' [MD.Text_ t]
    Paragraph (Inline inlines) -> MD.Paragraph_ $
      fmap (review (inlineAtomMdP inlineEmbedP)) inlines
    BlockEmbed embed -> review blockEmbedP embed

  fwd = \case
    MD.Heading_ h [MD.Text_ t] ->
      let h' = case h of
            1 -> Just H1
            2 -> Just H2
            3 -> Just H3
            _ -> Nothing
      in Header <$> h' <*> pure t
    MD.Paragraph_ inlines -> Paragraph . Inline
      <$> traverse (preview (inlineAtomMdP inlineEmbedP)) inlines
    node -> BlockEmbed <$> preview blockEmbedP node

documentMdP
  :: forall inlineEmbed blockEmbed.
     Prism' MD.Node blockEmbed
  -> Prism' MD.Node inlineEmbed
  -> Prism' MD.Node (Document blockEmbed inlineEmbed)
documentMdP blockEmbedP inlineEmbedP = prism' bwd fwd where
  blockMdP' :: Prism' MD.Node (Block blockEmbed inlineEmbed)
  blockMdP' = blockMdP blockEmbedP inlineEmbedP
  bwd = \case
    Document blocks -> MD.Document_ $ fmap (review blockMdP') blocks
  fwd = \case
    MD.Document_ blocks -> Document <$> traverse (preview blockMdP') blocks
    _                   -> Nothing

blockEmbedVoidP :: Prism' MD.Node Void
blockEmbedVoidP = prism' absurd (const Nothing)

inlineEmbedVoidP :: Prism' MD.Node Void
inlineEmbedVoidP = prism' absurd (const Nothing)

documentMdP' :: Prism' MD.Node (Document Void Void)
documentMdP' = documentMdP blockEmbedVoidP inlineEmbedVoidP

textMdP :: Iso' Text MD.Node
textMdP
  = iso (MD.commonmarkToNode options) (MD.nodeToCommonmark options Nothing)
  where options = []

foldText :: Fold Text (Term' Void Void)
foldText = textMdP . documentMdP' . re model

foldTerm :: Fold (Term' Void Void) Text
foldTerm = model . re documentMdP' . re textMdP

textDocument :: Text
textDocument = [text|
# important document

*this* is the important document you've heard about. **never** mention it to anyone
|]

documentTests :: Test ()
documentTests = tests
  [ do Just doc  <- pure $ textDocument ^? foldText
       Just doc' <- pure $ doc ^? foldTerm
       expectEq textDocument doc'
  ]
