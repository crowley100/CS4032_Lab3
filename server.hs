module Main where
 
import System.IO
import System.Exit
import System.Environment
import Network.Socket
import Network.BSD
import Control.Concurrent
import Control.Monad
import Data.List.Split
import Data.List
import Data.Map 
import qualified Data.Map as Map


myPool = 50

data Client = Client
    { clientID :: Int
    , clientNick :: String
    , clientConn :: Socket
    }

data Room = Room
    { roomID :: Int
    , roomName :: String
    , roomClients :: [String]
    } 

threadPoolIO :: Int -> (a -> IO b) -> IO (Chan a, Chan b)
threadPoolIO nr mutator = do
    input <- newChan
    output <- newChan
    forM_ [1..nr] $
        \_ -> forkIO (forever $ do
            i <- readChan input
            o <- mutator i
            writeChan output o)
    return (input, output)

-- init
runServer :: Int -> IO ()
runServer port = do
    sock <- socket AF_INET Stream 0            -- new socket
    setSocketOption sock ReuseAddr 1           -- make socket reuseable
    bind sock (SockAddrInet (fromIntegral port) iNADDR_ANY)   -- listen on port.
    listen sock 3                             
    (input,output) <- threadPoolIO myPool hdlConn   -- 50 workers
    -- testing
    -- init maps
    let rooms = empty
        clients = empty
    --    clients = Map empty
    --    
  
    
    --let str = roomName myRoom -- accessing elements of datatype
    --print str
    mainLoop sock input port
  
-- handle connections  
mainLoop :: Socket -> Chan (Int,(Socket, SockAddr)) -> Int -> IO ()
mainLoop sock input port = do
    conn <- accept sock     -- accept a new client connection
    writeChan input (port,conn)
    mainLoop sock input port        -- loop

-- server logic
hdlConn :: (Int,(Socket, SockAddr)) -> IO ()
hdlConn (port,(sock, _)) = do
    t <- myThreadId
    print t
    handle <- socketToHandle sock ReadWriteMode
    hSetBuffering handle NoBuffering -- Line??
    
    msg <- hGetContents handle -- hGetLine ?? MAYBE ERROR HANDLING HERE!!! (see procress req)
    let lines = words msg
    let hiMsg = myResponse msg "134.226.32.10" port
    print hiMsg
    
    -- watch for spaces in parsing (e.g. in join param 1(2))
    -- error handling here: accepted <- try (handler params) case accepted of Left error Right finish
    case head lines of
        "KILL_SERVICE" -> sClose sock
        "HELO" -> hPutStr handle hiMsg
        --"DISCONNECT:" -> clientDisc handle (splitColon $ lines!!2)
        --"JOIN_CHATROOM:" -> clientJoin handle (splitColon $ head lines) (splitColon $ lines!!3)
        --"LEAVE_CHATROOM:" -> clientLeave handle (read $ splitColon $ head lines) (splitColon $ lines!!1) (splitColon $ lines!!2) --nother read??
        --"CHAT:" -> clientChat (read $ splitColon $ head lines) (splitColon $ lines!!2) (splitColon $ lines!!3)
        _ -> putStrLn $ "Unknown Message:" ++ msg
    
    hClose handle
  
myResponse :: String -> String -> Int -> String
myResponse msg host port = msg ++ "\n" ++
                           "IP:" ++ host ++ "\n" ++
                           "Port:" ++ show port ++ "\n" ++
                           "StudentID:13333179"  
     
-- syntax?                      
splitColon :: String -> String
splitColon str = (splitOn ":" str) !! 1

-- WORKING HERE: LOOK AT HOW TO SET UP AN ENVIRONMENT TO ACCESS MAPS
--clientJoin :: Handle -> String -> String -> IO () -- return type?
--clientJoin handle roomName clientName
    
main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port
