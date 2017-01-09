
import qualified Data.ByteString as Bs

import qualified Network.Socket as So

import qualified System.IO as SI

import Auxiliars
import SecureUDP

main = do
    SI.hSetBuffering SI.stdout SI.NoBuffering
    putStrLn "Insert port (e.g. \"7272\"):"
    port <- fmap read getLine
    sock <- So.socket So.AF_INET So.Datagram So.defaultProtocol
    So.bind sock (So.SockAddrInet port $ So.tupleToHostAddress (0,0,0,0))
    let chcfg = ChannelConfig {
            socket = sock,
            resendTimeout = 280000000000, -- 0.28 seconds.
            maxResends = 5,
            allowed = (\_ -> True), -- Allow any incomming address.
            maxPacketSize = 500
        }
    mchst <- startChannel chcfg
    terminal mchst

terminal :: ChannelSt -> IO ()
terminal mchst = do
    recvs <- getReceived mchst
    mapM_ (\(a,m) -> putStrLn $ show a ++ " says: " ++ show m) recvs
    loss <- getLoss mchst
    mapM_ (\(a,m) -> putStrLn $ show a ++ " didn't ACKed: " ++ show m) loss
    putStrLn "Insert message (e.g. \"127.0.0.1:2000 Hello world!\"):"
    line <- Bs.getLine
    if line /= Bs.empty then let
        (dir,msg) = Bs.span ((char2word8 ' ') /=) line
        in sendMessages mchst [(readSockAddr $ map word82char $ Bs.unpack dir, Bs.tail msg)]
    else return()
    terminal mchst

readSockAddr :: String -> So.SockAddr
readSockAddr str = let
    (dir,_:port) = span (/=':') str
    [a,b,c,d] = map (char2word8 . head) $ splitWith '.' dir
    in So.SockAddrInet (read port) $ So.tupleToHostAddress (a,b,c,d)

splitWith :: Char -> String -> [String]
splitWith sep "" = [""]
splitWith sep (n:str) =
    if n == sep then
        [] : splitWith sep str
    else
        (\(w:nxts) -> (n:w):nxts) (splitWith sep str)