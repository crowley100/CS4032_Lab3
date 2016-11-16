import Network.Socket hiding (send, sendTo, recv, recvFrom)
import Network.Socket.ByteString
import qualified Data.ByteString.Char8 as B8
import System.IO
import System.Posix.Unistd
import System.Exit
import System.Environment
import Control.Concurrent
import Control.Monad.Fix (fix)
import Data.List

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
  fix $ \loop -> do
      msg <- getLine
      case head (words msg) of
        "join" -> do
            let myMsg = "JOIN_CHATROOM:" ++ ((words msg)!!1) ++ "\n" ++
                      "CLIENT_IP:0" ++ "\n" ++
                      "PORT:0" ++ "\n" ++
                      "CLIENT_NAME:" ++ ((words msg)!!2)
            hPutStrLn handle myMsg
        "leave" -> do
            let myMsg = "LEAVE_CHATROOM:" ++ ((words msg)!!1) ++ "\n" ++
                       "JOIN_ID:" ++ ((words msg)!!2) ++ "\n" ++
                       "CLIENT_NAME:" ++ ((words msg)!!3)
            hPutStrLn handle myMsg
        "disc" -> do
            let myMsg = "DISCONNECT:0" ++ "\n" ++
                       "PORT:0" ++ "\n" ++
                       "CLIENT_NAME:" ++ ((words msg)!!1)
            hPutStrLn handle myMsg
            hClose handle
            t <- myThreadId
            killThread t
        "chat" -> do
            let myMsg = "CHAT:" ++ ((words msg)!!1) ++ "\n" ++
                      "JOIN_ID:" ++ ((words msg)!!2) ++ "\n" ++
                      "CLIENT_NAME:" ++ ((words msg)!!3) ++ "\n" ++
                      "MESSAGE:" ++ ((words msg)!!4)
            hPutStrLn handle myMsg
        "helo" -> do
            let myMsg = "HELO BASE_TEST"
            hPutStrLn handle myMsg
        "kill" -> do
            let myMsg = "KILL_SERVICE"
            hPutStrLn handle myMsg
            hClose handle
            t <- myThreadId
            killThread t
        _ -> do 
            print "oops"
      let lineActions = repeat (hGetLine handle)
      myLines <- ioTakeWhile (isInfixOf "JOIN_ID") (isInfixOf "MESSAGE") (isInfixOf "Student") lineActions
      print "return msg..."
      let rmsg = concat myLines
      print rmsg
      loop
  print "sleeping"
  threadDelay 10000000 -- 10 seconds
  hClose handle

ioTakeWhile :: (a -> Bool) -> (a -> Bool) -> (a -> Bool) -> [IO a] -> IO [a]
ioTakeWhile pred1 pred2 pred3 actions = do
  x <- head actions
  if (pred1 x || pred2 x || pred3 x)
     then return [x]
     else (ioTakeWhile pred1 pred2 pred3 (tail actions)) >>= \xs -> return (x:xs)

main :: IO ()
main = withSocketsDo $ do
    (host:portStr:_) <- getArgs
    let port = read portStr :: Int
    client host port
