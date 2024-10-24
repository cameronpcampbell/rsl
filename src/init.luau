--!strict


--> Modules -------------------------------------------------------------------------------------------
local fs = require("@lune/fs")
local ParseFieldValue = require("./parseFieldValue.luau")
local Creator = require("./creator")
-------------------------------------------------------------------------------------------------------


--> Types ---------------------------------------------------------------------------------------------
type TokenConfig = {
    Kind: string,
    Pattern: string,
    Next: { TokenConfig }
}

type Token = {
    Kind: string,
    Value: string
}
-------------------------------------------------------------------------------------------------------


--> Variables -----------------------------------------------------------------------------------------
local TokensConfig: { TokenConfig } = {}


-- Comments ------------------------------------------
local CommentSingleToken: TokenConfig = {
    Kind = "COMMENT_SINGLE",
    Pattern = "^%-%-[^\n]+",
    Next = TokensConfig
}

local CommentMultiClosedToken: TokenConfig = {
    Kind = "COMMENT_MULTI_CLOSED",
    Pattern = "^%]%]",
    Next = TokensConfig
}

local CommentMultiInsideToken: TokenConfig = {
    Kind = "COMMENT_MULTI_INSIDE",
    Pattern = "^([^%]]+)%]?[^%]]",
    Next = {
        CommentMultiClosedToken
    }
}

local CommentMultiOpenToken: TokenConfig = {
    Kind = "COMMENT_MULTI_OPEN",
    Pattern = "^%-%-%[%[",
    Next = {
        CommentMultiInsideToken,
        CommentMultiClosedToken
    }
}
------------------------------------------------------


-- Fields --------------------------------------------
local BracketClosedToken: TokenConfig = {
    Kind = "BRACKET_CLOSED",
    Pattern = "^[ \n]*}[ \n]*",
    Next = TokensConfig
}

local FieldValueToken: TokenConfig = {} :: any

local FieldNameToken: TokenConfig = {
    Kind = "FIELD_NAME",
    Pattern = "^[\n ]*[^ \n=]+[ \n]*=[ \n]*",
    Next = {
        FieldValueToken
    }
}
------------------------------------------------------


-- Selectors -----------------------------------------
local TagSelectorToken: TokenConfig = {
    Kind = "TAG_SELECTOR",
    Pattern = "^[ \n]*%.[^ ,;\n]+[ \n]*{[ \n]*",
    Next = {
        FieldNameToken,
        BracketClosedToken
    }
}

local PseudoSelectorToken: TokenConfig = {
    Kind = "PSEUDO_SELECTOR",
    Pattern = "^[ \n]*::[^ ,;\n]+[ \n]*{[ \n]*",
    Next = {
        FieldNameToken,
        BracketClosedToken
    }
}

local EventSelectorToken: TokenConfig = {
    Kind = "EVENT_SELECTOR",
    Pattern = "^[ \n]*:[^ ,;\n]+[ \n]*{[ \n]*",
    Next = {
        FieldNameToken,
        BracketClosedToken
    }
}

local NameSelectorToken: TokenConfig = {
    Kind = "NAME_SELECTOR",
    Pattern = "^[ \n]*#[^ ,;\n]+[ \n]*{[ \n]*",
    Next = {
        FieldNameToken,
        BracketClosedToken
    }
}

local ClassSelectorToken: TokenConfig = {
    Kind = "CLASS_SELECTOR",
    Pattern = "^[ \n]*[^ ,;\n]+[ \n]*{[ \n]*",
    Next = {
        FieldNameToken,
        BracketClosedToken
    }
}
------------------------------------------------------


FieldValueToken.Kind = "FIELD_VALUE"
FieldValueToken.Pattern = "^[^\n]+\n"
FieldValueToken.Next = {
    BracketClosedToken,
    FieldNameToken,
    TagSelectorToken,
    PseudoSelectorToken,
    EventSelectorToken,
    NameSelectorToken,
    ClassSelectorToken,
}


table.insert(TokensConfig, CommentMultiOpenToken)
table.insert(TokensConfig, CommentSingleToken)
table.insert(TokensConfig, TagSelectorToken)
table.insert(TokensConfig, PseudoSelectorToken)
table.insert(TokensConfig, EventSelectorToken)
table.insert(TokensConfig, NameSelectorToken)
table.insert(TokensConfig, ClassSelectorToken)
table.insert(TokensConfig, BracketClosedToken)
-------------------------------------------------------------------------------------------------------


--> Functions -----------------------------------------------------------------------------------------
local function TableTraverseAndBuild(tble: { [any]: any }, path: { any })
    local curr: { [any]: any } = tble

    for _, item in path do
        local hasNext: { [any]: any } = curr[item]
        if not hasNext then
            local newCurr = {}
            curr[item] = newCurr
            curr = newCurr
        
        else
            curr = hasNext
        end
    end

    return curr
end

local function Tokenize(toParse: string)
    local nextTokensConfig: { TokenConfig } = TokensConfig

    local parsedTokens: { Token } = {}

    local cursorIdx, size = 1, #toParse

    while cursorIdx <= size do
        local matchFound = false

        for _, tokenConfig in nextTokensConfig do
            local start, finish = string.find(toParse, tokenConfig.Pattern, cursorIdx)
			if start == nil then continue end

            cursorIdx = (finish :: number) + 1

            table.insert(parsedTokens, {
                Kind = tokenConfig.Kind,
                Value = string.sub(toParse, start, finish)
            })

            matchFound = true
            nextTokensConfig = tokenConfig.Next

            break
        end

        if not matchFound then
            local start, finish = string.find(toParse, " *[^ \n]+", cursorIdx)
            if not start then print(string.sub(toParse, cursorIdx, #toParse)); break end
            cursorIdx = (finish :: number) + 1

            table.insert(parsedTokens, {
                Kind = "DEFAULT",
                Value = string.sub(toParse, start :: number, finish)
            })
        end
    end

    return parsedTokens
end

local function TokensToTable(parsedTokens: { Token })
    local tokensTable: { [string]: { [string]: any } } = {}

    local currPath: { string }, currParent: { [string]: any }?, currFieldName: string? = {}, nil, nil

    for _,token in parsedTokens do
        local kind, value = token.Kind, token.Value

        if
            kind == "TAG_SELECTOR" or kind == "PSEUDO_SELECTOR" or kind == "EVENT_SELECTOR" or
            kind == "NAME_SELECTOR" or kind == "CLASS_SELECTOR"
        then
            value = value:gsub("^[ \n]+", ""):gsub("[ \n]+{[ \n]+$", "")
            table.insert(currPath, value)
            currParent = TableTraverseAndBuild(tokensTable, currPath) :: { [string]: any }

        elseif token.Kind == "FIELD_NAME" then
            currFieldName = value:gsub("^[ \n]+", ""):gsub("[ \n]+=[ \n]+$", "")

        elseif token.Kind == "FIELD_VALUE" then
            if currParent == nil or currFieldName == nil then continue end
            currParent[currFieldName] = ParseFieldValue(currFieldName, value:match("^%s*(.-)%s*$") :: string)

        elseif token.Kind == "BRACKET_CLOSED" then
            table.remove(currPath)
            currParent = TableTraverseAndBuild(tokensTable, currPath) :: { [string]: any }
        end
    end

    return tokensTable
end


local function RslToLuau(path: string)
    local pathArr = path:gsub("[/]+", "/"):split("/")
    local pathArrLength = #pathArr
    local fileName = pathArr[pathArrLength]:gsub("[%.]+", ".")
    local fileExt = fileName:split(".")[2]

    assert(fileExt == "rsl", `Expected a \`.rsl\` file, got a \`{fileExt}\` file.`)

    local rslContent = fs.readFile(path)

    local luauContent = Creator(TokensToTable(Tokenize(rslContent)))

    pathArr[pathArrLength] = `{fileName}.luau`

    fs.writeFile(table.concat(pathArr, "/"), luauContent)
end
-------------------------------------------------------------------------------------------------------


-- Replace with path to your rsl file.
RslToLuau("../project/shared/styles/Button.rsl")
