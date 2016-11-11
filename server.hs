module Main where
 
import System.IO
import System.Exit
import System.Environment
import Network.Socket
import Network.BSD
import Control.Concurrent
import Control.Monad

myPool = 10

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
    (input,output) <- threadPoolIO myPool hdlConn   -- 5 worker threads waiting for connections
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
    hSetBuffering handle LineBuffering
    
    msg <- hGetLine handle
    let hiMsg = myResponse msg "134.226.32.10" port
    print hiMsg
    case head $ words msg of
        "KILL_SERVICE" -> sClose sock
        "HELO" -> hPutStr handle hiMsg
        _ -> putStrLn $ "Unknown Message:" ++ msg
    
    hClose handle
  
myResponse :: String -> String -> Int -> String
myResponse msg host port = msg ++ "\n" ++
                           "IP:" ++ host ++ "\n" ++
                           "Port:" ++ show port ++ "\n" ++
                           "StudentID:13333179"  
    
main :: IO ()
main = withSocketsDo $ do
    args <- getArgs
    let port = read $ head args :: Int
    runServer port
