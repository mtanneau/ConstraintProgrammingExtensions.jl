# =============================================================================
# =
# = Import from the FlatZinc format.
# =
# =============================================================================

@enum FznParserstate FznPredicate FznParameter FznVar FznConstraint FznSolve FznDone
@enum FznVariableType FznBool FznInt FznFloat

const FZN_PARAMETER_TYPES_PREFIX = String["bool", "int", "float", "set of int", "array"]

function Base.read!(io::IO, model::Optimizer)
    if !MOI.is_empty(model)
        error("Cannot read in file because model is not empty.")
    end

    # Start parsing loop.
    state = FznPredicate
    while !eof(io)
        # Consistency check: in FznDone state, nothing else can be read.
        if state == FznDone
            break
        end

        # Read an item from the file.
        item = get_fzn_item(io)
        
        # When get_fzn_item returns an empty line, it has not found any more 
        # item to parse.
        if isempty(item)
            break
        end

        # Depending on the state, different tokens are expected. Not all 
        # statees must be reached for all files: only FznSolve is mandatory, 
        # according to the grammar.
        if state == FznPredicate
            if startswith(item, "predicate")
                parse_predicate!(item, model)
            else
                state = FznParameter
            end
        end

        if state == FznParameter
            if any(startswith(item, par_type) for par_type in FZN_PARAMETER_TYPES_PREFIX)
                parse_parameter!(item, model)
            else
                state = FznVar
            end
        end

        if state == FznVar
            if startswith(item, "var")
                parse_variable!(item, model)
            else
                state = FznConstraint
            end
        end

        if state == FznConstraint
            if startswith(item, "constraint")
                parse_constraint!(item, model)
            else
                state = FznSolve
            end
        end

        if state == FznSolve
            if startswith(item, "solve")
                parse_constraint!(item, model)
                state = FznDone
            else
                error("Syntax error: expected a solve-item.")
            end
        end
    end

    return nothing
end

# -----------------------------------------------------------------------------
# - High-level parsing functions (FlatZinc items).
# -----------------------------------------------------------------------------

function parse_predicate!(item::AbstractString, model::Optimizer)
    error("Predicates are not supported.")
    return nothing
end

function parse_parameter!(item::AbstractString, model::Optimizer)
    error("Parameters are not supported.")
    return nothing
end

function parse_variable!(item::AbstractString, model::Optimizer)
    # Typical input: "var int: x1;"
    # Complex input: "array [1..5] of var int: x1;"
    # Complex input: "var int: x1 :: some_annotation = some_value;"

    # Split the item into interesting parts. 
    var_array, var_type, var_name, var_annotations, var_value = split_variable(item)

    # Parse the parts if need be.
    if var_array === nothing
        var_array_length = 1
    else
        var_array_length = parse_array_type(var_array)
    end

    var_type, var_multiplicity, var_min, var_max, var_allowed_values = parse_variable_type(var_type)

    if length(var_annotations) > 0
        @warn "Annotations are not supported and are currently ignored."
    end

    @show var_array_length
    @show var_type

    # Map to MOI constructs and add into the model.
    if var_multiplicity != "scalar"
        error("Set variables are not supported.")
    end



    return nothing
end

function parse_constraint!(item::AbstractString, model::Optimizer)
    error("Constraints are not supported.")
    return nothing
end

function parse_solve!(item::AbstractString, model::Optimizer)
    error("Solves are not supported.")
    return nothing
end

# -----------------------------------------------------------------------------
# - Low-level parsing functions (other grammar rules), independent of MOI.
# -----------------------------------------------------------------------------

function parse_array_type(var_array::AbstractString)::Union{Nothing, Int}
    # Typical input: "[1..5]"
    # The "1.." part is enforced by the grammar (with the exception of spaces).

    if length(var_array) == 0
        return nothing
    end

    # Get rid of the square brackets.
    @assert var_array[1] == '['
    @assert var_array[end] == ']'
    var_array = string(strip(var_array[2:end-1]))

    # Get rid of the leading "1".
    @assert var_array[1] == '1'
    var_array = string(strip(var_array[2:end]))

    # Get rid of the leading "..".
    @assert var_array[1] == '.'
    @assert var_array[2] == '.'
    var_array = string(strip(var_array[3:end]))

    # What remains should be an integer.
    return parse(Int, var_array)
end

function parse_range(range::AbstractString)
    # Typical inputs: "1..5", "1.5..2.4"
    @assert length(range) > 2

    low, hi = split(range, "..")
    low = strip(low)
    hi = strip(hi)

    # First, try to parse as integers: this is more restrictive than floats.
    try
        low_int = parse(Int, low)
        hi_int = parse(Int, hi)

        return (FznInt, low_int, hi_int)
    catch
        try
            low = parse(Float64, low)
            hi = parse(Float64, hi)

            return (FznFloat, low, hi)
        catch
            error("Ill-formed input: $low, $hi.")
            return nothing
        end
    end
end

function parse_set(set::AbstractString)
    # Typical inputs: "{}", "{1, 2, 3}"
    # Typical inputs: "{}", "{1.0, 2.1, 3.2}"
    @assert length(set) >= 2

    # Get rid of the curly braces
    @assert set[1] == '{'
    @assert set[end] == '}'
    set = set[2:end-1]
    
    # First, try to parse as integers: this is more restrictive than floats.
    try
        return (FznInt, parse_set_int(set))
    catch
        try
            return (FznFloat, parse_set_float(set))
        catch
            error("Ill-formed input: {$set}.")
            return nothing
        end
    end
end

function parse_set_int(set::AbstractString)
    # Typical inputs: "", "1, 2, 3"

    values = Int[]
    while length(set) > 0
        if occursin(',', set)
            value, set = split(set, ',', limit=2)
            push!(values, parse(Int, value))
        else
            push!(values, parse(Int, set))
            break
        end
    end

    return values
end

function parse_set_float(set::AbstractString)
    # Typical inputs: "", "1.0, 2.1, 3.2"

    values = Float64[]
    while length(set) > 0
        if occursin(',', set)
            value, set = split(set, ',', limit=2)
            push!(values, parse(Float64, value))
        else
            push!(values, parse(Float64, set))
            break
        end
    end

    return values
end

function parse_variable_type(var_type::AbstractString)
    # Typical inputs: "bool", "int", "set of int", "float"
    # Complex inputs: "1..5", "{1, 2, 3}", "1.5..1.7", "set of {1, 2, 3}", "set of 1..2"

    # Return tuple: 
    # - variable type: FznVariableType
    # - variable multiplicity: String ("scalar", "set")
    # - range minimum: Union{Nothing, Int, Float64}
    # - range maximum: Union{Nothing, Int, Float64}
    # - allowed values: Union{Nothing, Vector{Int}, Vector{Float64}}

    # Basic variable type.
    if var_type == "bool"
        return (FznBool, "scalar", nothing, nothing, nothing)
    elseif var_type == "int"
        return (FznInt, "scalar", nothing, nothing, nothing)
    elseif var_type == "float"
        return (FznFloat, "scalar", nothing, nothing, nothing)
    elseif var_type == "set of int"
        return (FznInt, "set", nothing, nothing, nothing)
    end

    # Sets, both ranges and sets in extension.
    if startswith(var_type, "set")
        @assert length(var_type) >= 4
        var_type = strip(var_type[4:end])
        @assert startswith(var_type, "of")
        @assert length(var_type) >= 3
        var_type = strip(var_type[3:end])

        if startswith(var_type, '{') && endswith(var_type, '}')
            var_type, var_values = parse_set(var_type)
            return (var_type, "set", nothing, nothing, var_values)
        end

        if !startswith(var_type, '{') && !endswith(var_type, '}') && occursin("..", var_type)
            var_type, var_min, var_max = parse_range(var_type)
            return (var_type, "set", var_min, var_max, nothing)
        end

        @assert false
    end

    # Ranges, of both integers and floats. Check this as a last step, because 
    # this might conflict with other cases ("set of 1..4", for instance).
    if occursin("..", var_type)
        var_type, var_min, var_max = parse_range(var_type)
        return (var_type, "scalar", var_min, var_max, nothing)
    end

    # Scalar variables, with sets given in extension.
    if startswith(var_type, '{') && endswith(var_type, '}')
        var_type, var_values = parse_set(var_type)
        return (var_type, "scalar", nothing, nothing, var_values)
    end

    # If no return previously, this could not be parsed.
    @assert false
end

# -----------------------------------------------------------------------------
# - String-level parsing functions.
# -----------------------------------------------------------------------------

function get_fzn_item(io::IO)
    # A FlatZinc item is delimited by a semicolon (;) at the end. Return one 
    # complete such item, excluding any comments.
    item = ""
    while !eof(io)
        c = read(io, Char)

        # A comment starts with a percent (%) and ends at the end of the line.
        # Stop reading this character and continue normally at the next line.
        if c == '%'
            readline(io)

            # If something was read, return this item. If not, continue reading.
            if length(string(strip(item))) == 0
                continue
            else
                break
            end
        end

        # Push the new character into the string.
        item *= c

        # An item is delimited by a semicolon.
        if c == ';'
            break
        end
    end
    return string(strip(item))
end

function split_variable(item::AbstractString)
    # Typical input: "var int: x1;" -> scalar
    # Complex input: "array [1..5] of var int: x1;" -> array
    # Complex input: "var int: x1 :: some_annotation = some_value;" -> scalar

    @assert length(item) > 4

    if startswith(item, "var")
        return split_variable_scalar(item)
    elseif startswith(item, "array") && occursin("var", item)
        return split_variable_array(item)
    else
        @assert false
    end
end

function split_variable_scalar(item::AbstractString)
    # Get rid of the "var" keyword at the beginning. 
    @assert item[1:3] == "var"
    item = lstrip(item[4:end])

    # Split on the colon (:): the type of the variable is before.
    var_type, item = split(item, ':', limit=2)
    var_type = strip(var_type)
    item = lstrip(item)

    # Potentially split on the double colon (::) to detect annotations, then
    # on the equal (=) to detect literal values.
    if occursin("::", item)
        var_name, item = split(item, "::", limit=2)
        var_name = strip(var_name)
        item = lstrip(item)

        if occursin('=', item)
            var_annotations, item = split(item, '=', limit=2)
            var_annotations = strip(var_annotations)
            item = lstrip(item)

            var_value, item = split(item, ';', limit=2)
            var_value = strip(var_value)
        else
            var_annotations, item = split(item, ';', limit=2)
            var_annotations = strip(var_annotations)
            var_value = ""
        end
    else
        var_annotations = ""

        if occursin('=', item)
            var_name, item = split(item, '=', limit=2)
            var_name = strip(var_name)
            item = lstrip(item)

            var_value, item = split(item, ';', limit=2)
            var_value = strip(var_value)
        else
            var_name, item = split(item, ';', limit=2)
            var_name = strip(var_name)
            var_value = ""
        end
    end
    
    return ("", var_type, var_name, var_annotations, var_value)
end

function split_variable_array(item::AbstractString)
    # Get rid of the "array" keyword at the beginning. 
    @assert item[1:5] == "array"
    item = lstrip(item[6:end])

    # Split on the "of" keyword: the array definition is before, the rest is a 
    # normal variable definition.
    var_array, item = split(item, "of", limit=2)
    var_array = strip(var_array)
    item = string(lstrip(item))

    # Parse the rest of the line.
    _, var_type, var_name, var_annotations, var_value = split_variable_scalar(item)
    
    return (var_array, var_type, var_name, var_annotations, var_value)
end
