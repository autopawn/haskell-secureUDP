module Auxiliars where

import qualified Data.ByteString as Bs
import qualified Data.Word as W

char2word8 :: Char -> W.Word8
char2word8 ch = fromIntegral (fromEnum ch)

word82char :: W.Word8 -> Char
word82char w8 = toEnum $ fromIntegral w8

-- | Parses an unsigned Int from Word8's in little endian.
parseInt :: [W.Word8] -> Int
parseInt [] = 0
parseInt (x:xs) = (fromIntegral x)+256*(parseInt xs)

-- | Converts an unsigned Int to Word8's in little endian.
dataInt :: Int -> [W.Word8]
dataInt v = dataInt' 4 v
dataInt' :: Int -> Int -> [W.Word8]
dataInt' 0 _ = []
dataInt' l v = (fromIntegral $ fromEnum $ rem v 256) : dataInt' (l-1) (div v 256)

{-|
    Returns the type of message ('a' for acknowledged, 'm' for message or '?' for unknown),
    it's identification label and the data on it.
-}
bstrKind :: Bs.ByteString -> (Char,Int,Bs.ByteString)
bstrKind bstr = let
    ubstr = Bs.unpack bstr
    top = word82char $ head ubstr
    ide = parseInt $ take 4 $ tail ubstr
    in if Bs.length bstr >= 5 && (top == 'a' || top == 'm') then
        (top, ide, Bs.drop 5 bstr)
    else ('?', 0, Bs.empty)
