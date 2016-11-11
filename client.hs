import Network.Socket hiding (send, sendTo, recv, recvFrom)
import Network.Socket.ByteString
import qualified Data.ByteString.Char8 as B8
import System.IO
import System.Posix.Unistd
import System.Exit
import System.Environment


client :: String -> Int -> IO ()
client host port = withSocketsDo $ do
                addrInfo <- getAddrInfo Nothing (Just host) (Just $ show port)
                let serverAddr = head addrInfo
                sock <- socket (addrFamily serverAddr) Stream defaultProtocol
                connect sock (addrAddress serverAddr)
                msgSender sock

msgSender :: Socket -> IO ()
msgSender sock = do
  handle <- socketToHandle sock ReadWriteMode
  hSetBuffering handle LineBuffering
  putStrLn "Enter message..."
  msg <- getLine
  hPutStrLn handle msg
  rMsg <- hGetContents handle
  putStrLn rMsg
  hClose handle

main :: IO ()
main = withSocketsDo $ do
    (host:portStr:_) <- getArgs
    let port = read portStr :: Int
    client host port
