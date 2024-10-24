--!strict


--> Functions -----------------------------------------------------------------------------------------
local function Unindent(str: any)
    return str:gsub("        ", ""):gsub("^[ \n]+", ""):gsub("[ \n]+$", "")
end

local function TableStringify(tble: any)
    local stringified = "{"

    for ik, v in tble do
        stringified ..= `\n    ["{ik}"] = {v},`
    end

    return stringified .. "\n}"
end

local function TableMap<IK, V, O>(tble: { [IK]: V }, fn: (item: V, idxOrKey: IK, idx: number) -> O)
    local tbleLength = #tble
    local newTble = table.create(tbleLength)

    local idx = 1
    for idxOrKey, item in tble do
        newTble[idx] = fn(item, idxOrKey, idx)
        idx += 1
    end

    return newTble
end

local function SepPropsAndRules(data: { [string]: string })
    local properties: { [any]: any }, rules: { [any]: any } = {}, {}

    for key, value in data do
        local addTo = if typeof(value) == "table" then rules else properties
        addTo[key] = value
    end

    return properties, rules
end

local function CreateStyleRule(data: { [string]: string }, selector: string, baseIdx: string | number, parent: string?)
    local properties, rules = SepPropsAndRules(data)

    return Unindent(`                                                    \
        local StyleRule_{baseIdx} = Instance.new("StyleRule")            \
        StyleRule_{baseIdx}.Selector = "{selector}"                      \
        StyleRule_{baseIdx}:SetProperties({TableStringify(properties)})  \
        StyleRule_{baseIdx}.Parent = {parent or "StyleSheet"}            \
                                                                         \
        {table.concat(TableMap(rules, function(data, selector, idx)
            return CreateStyleRule(data :: any, selector :: any, `{baseIdx}_{idx}`, `StyleRule_{baseIdx}`) :: any
        end), "\n\n")}                                                   \
    `)
end
-------------------------------------------------------------------------------------------------------


return function (styleTable: { [string]: { [string]: any } })
    local source = Unindent(`                                                 \
        local StyleSheet = Instance.new("StyleSheet")                         \
                                                                              \
        {table.concat(TableMap(styleTable, CreateStyleRule :: any), "\n\n")}  \
                                                                              \
        StyleSheet.Parent = script                                            \
                                                                              \
        return StyleSheet                                                     \
    `)
    return source
end
