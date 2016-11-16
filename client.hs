import Network.Socket hiding (send, sendTo, recv, recvFrom)
import Network.Socket.ByteString
import qualified Data.ByteString.Char8 as B8
import System.IO
import System.Posix.Unistd
import System.Exit
import System.Environment
import Control.Concurrent
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
  --msg <- getLine
  let msg = "JOIN_CHATROOM:room1" ++ "\n" ++
            "CLIENT_IP:0" ++ "\n" ++
            "PORT:0" ++ "\n" ++
            "CLIENT_NAME:dave"
  hPutStrLn handle msg
  rMsg <- hGetLine handle
  print rMsg
  --{-
  let msg2 = "LEAVE_CHATROOM:52" ++ "\n" ++
            "JOIN_ID:52" ++ "\n" ++
            "CLIENT_NAME:dave"
  hPutStrLn handle msg2
  rMsg2 <- hGetLine handle
  print rMsg2 ---}
  print "sleeping"
  threadDelay 10000000 -- 10 seconds
  hClose handle

main :: IO ()
main = withSocketsDo $ do
    (host:portStr:_) <- getArgs
    let port = read portStr :: Int
    client host port
