import qualified Language.ECMAScript3.Parser as Parser
import Language.ECMAScript3.Syntax
import Control.Monad
import Control.Applicative
import Data.Map as Map (Map, insert, lookup, union, toList, empty)
import Debug.Trace
import Value

--
-- Evaluate functions
--

evalExpr :: StateT -> Expression -> StateTransformer Value
evalExpr env (VarRef (Id id)) = stateLookup env id
evalExpr env (IntLit int) = return $ Int int
evalExpr env (BoolLit bool) = return $ Bool bool
evalExpr env (InfixExpr op expr1 expr2) = do
    v1 <- evalExpr env expr1
    v2 <- evalExpr env expr2
    infixOp env op v1 v2
evalExpr env (AssignExpr OpAssign (LVar var) expr) = do
    stateLookup env var -- crashes if the variable doesn't exist
    e <- evalExpr env expr
    setVar var e
-------------------------------------------------------------------------------------
evalExpr env (StringLit str) = return $ String str
-------------------------------------------------------------------------------------
--Array

evalExpr env (ArrayLit []) = return $ Array []
evalExpr env (ArrayLit (x:xs)) = do
    a <- evalExpr env x
    (Array b) <- evalExpr env (ArrayLit xs)
    return $ Array ([a] ++ b)
    
-----------------------------------------------------------------------------------

evalStmt :: StateT -> Statement -> StateTransformer Value
evalStmt env EmptyStmt = return Nil
evalStmt env (VarDeclStmt []) = return Nil
evalStmt env (VarDeclStmt (decl:ds)) =
    varDecl env decl >> evalStmt env (VarDeclStmt ds)
evalStmt env (ExprStmt expr) = evalExpr env expr
-------------------------------------------------------------------------------------
-- LOOPS
-- TODO: modularizar os for's
-- TODO: implementar comandos break e continue
-- do while
evalStmt env (DoWhileStmt stmt expr) = do
    v <- evalStmt env stmt
    Bool b <- evalExpr env expr

    case v of
        Break -> return Break
        _ -> if b then evalStmt env (DoWhileStmt stmt expr) else return Nil
-- while
evalStmt env (WhileStmt expr stmt) = do
    Bool b <- evalExpr env expr
    if b then do
        v <- evalStmt env stmt
        case v of
            Break -> return Break
            _ -> evalStmt env (WhileStmt expr stmt)
    else
        return Nil
-- for
evalStmt env (ForStmt init test incr stmt) = do
    case init of
        NoInit -> return Nil
        VarInit vars -> evalStmt env (VarDeclStmt vars)
        ExprInit expr -> evalExpr env expr
    case test of
        Nothing -> do
            -- loop infinito
            v <- evalStmt env stmt
            case v of
                Break -> return Break
                _ -> evalStmt env (ForStmt NoInit test incr stmt)

        Just testExpr -> do
            -- testa condicao
            Bool b <- evalExpr env testExpr
            if b then do
                -- roda statement
                v <- evalStmt env stmt

                case v of
                    Break -> return Break
                    _ -> do
                        -- incrementa contador
                        case incr of 
                            Nothing -> return Nil
                            Just incrExpr -> do
                                -- incrementa
                                evalExpr env incrExpr
                                -- loop
                                evalStmt env (ForStmt NoInit test incr stmt)
            else 
                return Nil
-------------------------------------------------------------------------------------
-- BLOCK
evalStmt env (BlockStmt []) = return Nil
evalStmt env (BlockStmt (stmt:stmts)) = do
    v <- evalStmt env stmt
    case v of
        Break -> return Break
        _ -> evalStmt env (BlockStmt stmts)
-------------------------------------------------------------------------------------
-- IF
-- single if
evalStmt env (IfSingleStmt expr stmt) = do
    Bool b <- evalExpr env expr
    if b then do
        a <- evalStmt env stmt
        return a
    else 
        return Nil
-- if else
evalStmt env (IfStmt expr ifStmt elseStmt) = do
    Bool b <- evalExpr env expr
    if b then do
        a <- evalStmt env ifStmt
        return a
    else do
        a <- evalStmt env elseStmt
        return a
-------------------------------------------------------------------------------------
-- BREAK
evalStmt env (BreakStmt m) = return Break
-------------------------------------------------------------------------------------

-- Do not touch this one :)
evaluate :: StateT -> [Statement] -> StateTransformer Value
evaluate env [] = return Nil
evaluate env stmts = foldl1 (>>) $ map (evalStmt env) stmts

--
-- Operators
--

infixOp :: StateT -> InfixOp -> Value -> Value -> StateTransformer Value
infixOp env OpAdd  (Int  v1) (Int  v2) = return $ Int  $ v1 + v2
infixOp env OpSub  (Int  v1) (Int  v2) = return $ Int  $ v1 - v2
infixOp env OpMul  (Int  v1) (Int  v2) = return $ Int  $ v1 * v2
infixOp env OpDiv  (Int  v1) (Int  v2) = return $ Int  $ div v1 v2
infixOp env OpMod  (Int  v1) (Int  v2) = return $ Int  $ mod v1 v2
infixOp env OpLT   (Int  v1) (Int  v2) = return $ Bool $ v1 < v2
infixOp env OpLEq  (Int  v1) (Int  v2) = return $ Bool $ v1 <= v2
infixOp env OpGT   (Int  v1) (Int  v2) = return $ Bool $ v1 > v2
infixOp env OpGEq  (Int  v1) (Int  v2) = return $ Bool $ v1 >= v2
infixOp env OpEq   (Int  v1) (Int  v2) = return $ Bool $ v1 == v2
infixOp env OpEq   (Bool v1) (Bool v2) = return $ Bool $ v1 == v2
infixOp env OpNEq  (Bool v1) (Bool v2) = return $ Bool $ v1 /= v2
infixOp env OpLAnd (Bool v1) (Bool v2) = return $ Bool $ v1 && v2
infixOp env OpLOr  (Bool v1) (Bool v2) = return $ Bool $ v1 || v2
-------------------------------------------------------------------------------------
infixOp env OpAdd  (String  v1) (String  v2) = return $ String  $ v1 ++ v2
-------------------------------------------------------------------------------------

--
-- Environment and auxiliary functions
--

environment :: Map String Value
environment = Map.empty

stateLookup :: StateT -> String -> StateTransformer Value
stateLookup env var = ST $ \s ->
    -- this way the error won't be skipped by lazy evaluation
    case Map.lookup var (union s env) of
        Nothing -> error $ "Variable " ++ show var ++ " not defiend."
        Just val -> (val, s)

varDecl :: StateT -> VarDecl -> StateTransformer Value
varDecl env (VarDecl (Id id) maybeExpr) = do
    case maybeExpr of
        Nothing -> setVar id Nil
        (Just expr) -> do
            val <- evalExpr env expr
            setVar id val

setVar :: String -> Value -> StateTransformer Value
setVar var val = ST $ \s -> (val, insert var val s)

--
-- Types and boilerplate
--

type StateT = Map String Value
data StateTransformer t = ST (StateT -> (t, StateT))

instance Monad StateTransformer where
    return x = ST $ \s -> (x, s)
    (>>=) (ST m) f = ST $ \s ->
        let (v, newS) = m s
            (ST resF) = f v
        in resF newS

instance Functor StateTransformer where
    fmap = liftM

instance Applicative StateTransformer where
    pure = return
    (<*>) = ap

--
-- Main and results functions
--

showResult :: (Value, StateT) -> String
showResult (val, defs) =
    show val ++ "\n" ++ show (toList $ union defs environment) ++ "\n"

getResult :: StateTransformer Value -> (Value, StateT)
getResult (ST f) = f Map.empty

main :: IO ()
main = do
    js <- Parser.parseFromFile "Main.js"
    let statements = unJavaScript js
    putStrLn $ "AST: " ++ (show $ statements) ++ "\n"
    putStr $ showResult $ getResult $ evaluate environment statements
