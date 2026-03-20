--[[
脚本名字: FormatUtil
脚本文件: FormatUtil.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/FormatUtil
]]

local FormatUtil = {}

local COMPACT_NUMBER_UNITS = {
    { Value = 1e30, Suffix = "No" },
    { Value = 1e27, Suffix = "Oc" },
    { Value = 1e24, Suffix = "Sp" },
    { Value = 1e21, Suffix = "Sx" },
    { Value = 1e18, Suffix = "Qi" },
    { Value = 1e15, Suffix = "Qa" },
    { Value = 1e12, Suffix = "T" },
    { Value = 1e9, Suffix = "B" },
    { Value = 1e6, Suffix = "M" },
    { Value = 1e3, Suffix = "K" },
}

local function trimTrailingZeros(numberText)
    local trimmed = string.gsub(numberText, "(%..-)0+$", "%1")
    trimmed = string.gsub(trimmed, "%.$", "")
    return trimmed
end

function FormatUtil.RoundToDecimals(value, decimals)
    local numericValue = tonumber(value) or 0
    local places = math.max(0, math.floor(tonumber(decimals) or 0))
    if places <= 0 then
        if numericValue >= 0 then
            return math.floor(numericValue + 0.5)
        end

        return math.ceil(numericValue - 0.5)
    end

    local factor = 10 ^ places
    if numericValue >= 0 then
        return math.floor((numericValue * factor) + 0.5) / factor
    end

    return math.ceil((numericValue * factor) - 0.5) / factor
end

function FormatUtil.CeilNonNegative(value)
    return math.max(0, math.ceil((tonumber(value) or 0) - 1e-9))
end

function FormatUtil.FormatWithCommas(value, maxDecimals)
    local numericValue = tonumber(value) or 0
    local sign = numericValue < 0 and "-" or ""
    local decimals = math.max(0, math.floor(tonumber(maxDecimals) or 0))
    local absoluteValue = math.abs(numericValue)
    local wholeText = nil
    local fractionText = ""

    if decimals > 0 then
        local roundedValue = math.abs(FormatUtil.RoundToDecimals(numericValue, decimals))
        local formatString = string.format("%%.%df", decimals)
        local roundedText = string.format(formatString, roundedValue)
        local parsedWholeText, parsedFractionText = string.match(roundedText, "^(%d+)%.(%d+)$")
        if parsedWholeText then
            wholeText = parsedWholeText
            fractionText = string.gsub(parsedFractionText or "", "0+$", "")
            if fractionText ~= "" then
                fractionText = "." .. fractionText
            end
        else
            wholeText = roundedText
        end
    else
        wholeText = tostring(math.floor(absoluteValue))
    end

    local formatted = wholeText:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if formatted:sub(1, 1) == "," then
        formatted = formatted:sub(2)
    end

    return sign .. formatted .. fractionText
end

function FormatUtil.FormatCompactNumber(value, maxDecimals)
    local numericValue = math.max(0, tonumber(value) or 0)
    local decimalsOverride = tonumber(maxDecimals)
    if numericValue < 1000 then
        if math.abs(numericValue - math.floor(numericValue)) < 0.001 then
            return tostring(math.floor(numericValue))
        end

        local decimals = numericValue >= 100 and 0 or (numericValue >= 10 and 1 or 2)
        if decimalsOverride ~= nil then
            decimals = math.max(0, math.floor(decimalsOverride))
        end

        local formatString = string.format("%%.%df", decimals)
        return trimTrailingZeros(string.format(formatString, numericValue))
    end

    for _, unit in ipairs(COMPACT_NUMBER_UNITS) do
        if numericValue >= unit.Value then
            local scaled = numericValue / unit.Value
            local decimals = 2
            if scaled >= 100 then
                decimals = 0
            elseif scaled >= 10 then
                decimals = 1
            end

            if decimalsOverride ~= nil then
                decimals = math.max(0, math.floor(decimalsOverride))
            end

            local formatString = string.format("%%.%df", decimals)
            return trimTrailingZeros(string.format(formatString, scaled)) .. unit.Suffix
        end
    end

    return tostring(math.floor(numericValue))
end

function FormatUtil.FormatCompactCurrency(value, maxDecimals)
    return "$" .. FormatUtil.FormatCompactNumber(value, maxDecimals)
end

function FormatUtil.FormatCompactCurrencyPerSecond(value, maxDecimals)
    return FormatUtil.FormatCompactCurrency(value, maxDecimals) .. "/S"
end

function FormatUtil.FormatDurationDaysHoursMinutes(totalSeconds)
    local clampedSeconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local totalMinutes = math.floor(clampedSeconds / 60)
    local days = math.floor(totalMinutes / (24 * 60))
    local hours = math.floor((totalMinutes % (24 * 60)) / 60)
    local minutes = totalMinutes % 60
    return string.format("%02d:%02d:%02d", days, hours, minutes)
end

return FormatUtil
