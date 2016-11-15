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
  --msg <- getLine
  let msg = "JOIN_CHATROOM: room1" ++ "\n" ++
            "CLIENT_IP: 0" ++ "\n" ++
            "PORT: 0" ++ "\n" ++
            "CLIENT_NAME: dave"
  print msg
  hPutStrLn handle msg
  rMsg <- hGetContents handle
  putStrLn rMsg
  hClose handle

main :: IO ()
main = withSocketsDo $ do
    (host:portStr:_) <- getArgs
    let port = read portStr :: Int
    client host port
