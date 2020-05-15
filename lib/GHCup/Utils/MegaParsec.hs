{-# LANGUAGE CPP                  #-}
{-# LANGUAGE OverloadedStrings    #-}

module GHCup.Utils.MegaParsec where

import           GHCup.Types

import           Control.Applicative
import           Control.Monad
#if !MIN_VERSION_base(4,13,0)
import           Control.Monad.Fail             ( MonadFail )
#endif
import           Data.Functor
import           Data.Maybe
import           Data.Text                      ( Text )
import           Data.Versions
import           Data.Void

import qualified Data.Text                     as T
import qualified Text.Megaparsec               as MP


choice' :: (MonadFail f, MP.MonadParsec e s f) => [f a] -> f a
choice' []       = fail "Empty list"
choice' [x     ] = x
choice' (x : xs) = MP.try x <|> choice' xs


parseUntil :: MP.Parsec Void Text a -> MP.Parsec Void Text Text
parseUntil p = do
  (MP.try (MP.lookAhead p) $> mempty)
    <|> (do
          c  <- T.singleton <$> MP.anySingle
          c2 <- parseUntil p
          pure (c `mappend` c2)
        )

parseUntil1 :: MP.Parsec Void Text a -> MP.Parsec Void Text Text
parseUntil1 p = do
  i1 <- MP.getOffset
  t <- parseUntil p
  i2 <- MP.getOffset
  if i1 == i2 then fail "empty parse" else pure t



-- | Parses e.g.
--   * armv7-unknown-linux-gnueabihf-ghc
--   * armv7-unknown-linux-gnueabihf-ghci
ghcTargetBinP :: Text -> MP.Parsec Void Text (Maybe Text, Text)
ghcTargetBinP t =
  (,)
    <$> (   MP.try
            (Just <$> (parseUntil1 (MP.chunk "-" *> MP.chunk t)) <* MP.chunk "-"
            )
        <|> (flip const Nothing <$> mempty)
        )
    <*> (MP.chunk t <* MP.eof)


-- | Extracts target triple and version from e.g.
--   * armv7-unknown-linux-gnueabihf-8.8.3
--   * armv7-unknown-linux-gnueabihf-8.8.3
ghcTargetVerP :: MP.Parsec Void Text GHCTargetVersion
ghcTargetVerP =
  (\x y -> GHCTargetVersion x y)
    <$> (MP.try (Just <$> (parseUntil1 (MP.chunk "-" *> verP)) <* MP.chunk "-")
        <|> (flip const Nothing <$> mempty)
        )
    <*> (version' <* MP.eof)
 where
  verP :: MP.Parsec Void Text Text
  verP = do
    v <- version'
    let startsWithDigists =
          and
            . take 3
            . join
            . (fmap . fmap)
                (\case
                  (Digits _) -> True
                  (Str    _) -> False
                )
            $ (_vChunks v)
    if startsWithDigists && not (isJust (_vEpoch v))
      then pure $ prettyVer v
      else fail "Oh"