# =============================================================================
# =
# = FlatZinc model.
# =
# =============================================================================

mutable struct VariableInfo
    index::MOI.VariableIndex
    name::String
    set::MOI.AbstractSet
end

mutable struct ConstraintInfo
    index::MOI.ConstraintIndex
    # FlatZinc does not allow constraint names.
    f::MOI.AbstractFunction
    s::MOI.AbstractSet
    output_as_part_of_variable::Bool
end

mutable struct Optimizer <: MOI.AbstractOptimizer
    # A mapping from the MOI.VariableIndex to the variable object.
    # VariableInfo also stores some additional fields like the type of variable.
    variable_info::CleverDicts.CleverDict{MOI.VariableIndex, VariableInfo}

    # A mapping from the MOI.ConstraintIndex to the variable object.
    # ConstraintInfo also stores some additional fields like the type of 
    # constraint. Deletion of constraints is not supported (having a vector 
    # ensures that the order in which constraints are added is respected when 
    # outputting the model, which makes testing easier).
    constraint_info::Vector{ConstraintInfo}

    # For FlatZinc-level sets/arrays, map the constraints that are defined on 
    # sets/arrays to the assigned name of the set/array. This structure is 
    # built when outputting the FZN file.
    sets_id::Dict{MOI.ConstraintIndex, String}
    arrs_id::Dict{MOI.ConstraintIndex, String}

    # Memorise the objective sense and the function separately.
    # The function can only be a single variable, as per FlatZinc limitations.
    objective_sense::MOI.OptimizationSense
    objective_function::Union{Nothing, MOI.SingleVariable}

    # Map names to MOI variable indices.
    name_to_var::Dict{String, MOI.VariableIndex}

    """
        Optimizer()

    Create a new Optimizer object.
    """
    function Optimizer()
        model = new()
        model.variable_info =
            CleverDicts.CleverDict{MOI.VariableIndex, VariableInfo}()
        model.constraint_info = ConstraintInfo[]

        model.objective_sense = MOI.FEASIBILITY_SENSE
        model.objective_function = nothing

        model.sets_id = Dict{MOI.ConstraintIndex, String}()
        model.arrs_id = Dict{MOI.ConstraintIndex, String}()

        model.name_to_var = Dict{String, MOI.VariableIndex}()

        MOI.empty!(model)
        return model
    end
end

function Base.show(io::IO, ::Optimizer)
    print(io, "A FlatZinc (fzn) model")
    return
end

function MOI.empty!(model::Optimizer)
    empty!(model.variable_info)
    empty!(model.constraint_info)

    model.objective_sense = MOI.FEASIBILITY_SENSE
    model.objective_function = nothing

    model.sets_id = Dict{MOI.ConstraintIndex, String}()
    model.arrs_id = Dict{MOI.ConstraintIndex, String}()

    model.name_to_var = Dict{String, MOI.VariableIndex}()

    return
end

function MOI.is_empty(model::Optimizer)
    !isempty(model.variable_info) && return false
    !isempty(model.constraint_info) && return false
    model.objective_sense != MOI.FEASIBILITY_SENSE && return false
    model.objective_function !== nothing && return false
    return true
end

# Set the objective.

function MOI.get(model::Optimizer, ::MOI.ObjectiveFunction{MOI.SingleVariable})
    return model.objective_function
end

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveFunction{MOI.SingleVariable},
    f::MOI.SingleVariable,
)
    model.objective_function = f
    return nothing
end

function MOI.get(model::Optimizer, ::MOI.ObjectiveSense)
    return model.objective_sense
end

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveSense,
    s::MOI.OptimizationSense,
)
    model.objective_sense = s
    return nothing
end

# Helpers.

function _create_variable(
    model::Optimizer,
    set::Union{MOI.AbstractScalarSet, MOI.Reals},
)
    index = CleverDicts.add_item(
        model.variable_info,
        VariableInfo(MOI.VariableIndex(0), "", set),
    )
    model.variable_info[index].index = index
    return index
end

function _create_constraint(
    model::Optimizer,
    f::F,
    set::S,
    as_part_of_variable::Bool,
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    index = MOI.ConstraintIndex{F, S}(length(model.constraint_info) + 1)
    push!(
        model.constraint_info,
        ConstraintInfo(index, f, set, as_part_of_variable),
    )
    return index
end

# Names. 
# No support for constraint names in fzn, hence no ConstraintName.

function MOI.get(model::Optimizer, ::MOI.VariableName, v::MOI.VariableIndex)
    return model.variable_info[v].name
end

function MOI.set(
    model::Optimizer,
    ::MOI.VariableName,
    v::MOI.VariableIndex,
    name::AbstractString,
)
    model.variable_info[v].name = string(name)
    return
end

# Variables.

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{F},
) where {
    F <: Union{
        MOI.EqualTo{Float64},
        MOI.LessThan{Float64},
        MOI.GreaterThan{Float64},
        MOI.Interval{Float64},
        MOI.EqualTo{Int},
        MOI.LessThan{Int},
        MOI.GreaterThan{Int},
        MOI.Interval{Int},
        MOI.EqualTo{Bool},
        MOI.ZeroOne,
        MOI.Integer,
    },
}
    return true
end

function MOI.add_variable(model::Optimizer)
    return _create_variable(model, MOI.Reals(1))
end

function MOI.add_constrained_variables(
    model::Optimizer,
    sets::AbstractVector{<:MOI.AbstractScalarSet},
)
    # TODO: memorise that these variables are part of the same call, so that 
    # the generated FlatZinc is shorter (array of variables)? This would 
    # require that all sets are identical, though.
    vidx = [_create_variable(model, sets[i]) for i in 1:length(sets)]
    cidx = [
        _create_constraint(model, MOI.SingleVariable(vidx[i]), sets[i], true) for i in 1:length(sets)
    ]
    return vidx, cidx
end

function MOI.add_constrained_variable(
    model::Optimizer,
    set::MOI.AbstractScalarSet,
)
    # Unlike FZN, MOI does not assume that a variable >= 0.0 is any different 
    # from a >= 0 (int).
    vidx = _create_variable(model, set)
    cidx = _create_constraint(model, MOI.SingleVariable(vidx), set, true)
    return vidx, cidx
end

function MOI.is_valid(model::Optimizer, v::MOI.VariableIndex)
    return haskey(model.variable_info, v)
end

function MOI.get(model::Optimizer, ::MOI.NumberOfVariables)
    return length(model.variable_info)
end

function MOI.get(model::Optimizer, ::MOI.ListOfVariableIndices)
    return collect(keys(model.variable_info))
end

# Constraints.

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{F, S},
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    info = get(model.constraint_info, c.value, nothing)
    return info !== nothing && typeof(info.s) == S
end

function MOI.add_constraint(
    model::Optimizer,
    f::F,
    s::S,
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    index = MOI.ConstraintIndex{F, S}(length(model.constraint_info) + 1)
    push!(model.constraint_info, ConstraintInfo(index, f, s, false))
    return index
end

function MOI.get(
    model::Optimizer,
    ::MOI.ConstraintFunction,
    c::MOI.ConstraintIndex{F, S},
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    return model.constraint_info[c.value].f
end

function MOI.get(
    model::Optimizer,
    ::MOI.ConstraintSet,
    c::MOI.ConstraintIndex{F, S},
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    return model.constraint_info[c.value].s
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.SingleVariable},
    ::Type{MOI.LessThan{Int}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.SingleVariable},
    ::Type{MOI.LessThan{Float64}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.SingleVariable},
    ::Type{CP.Strictly{MOI.LessThan{Float64}}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.SingleVariable},
    ::Type{CP.Domain{Int}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.SingleVariable},
    ::Type{MOI.Interval{Float64}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{CP.Element{Int}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{CP.Element{Bool}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{CP.Element{Float64}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{CP.MaximumAmong},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{CP.MinimumAmong},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Int}},
    ::Type{MOI.EqualTo{Int}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Int}},
    ::Type{MOI.LessThan{Int}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Int}},
    ::Type{CP.DifferentFrom{Int}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Float64}},
    ::Type{MOI.EqualTo{Float64}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Float64}},
    ::Type{MOI.LessThan{Float64}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Float64}},
    ::Type{CP.Strictly{MOI.LessThan{Float64}}},
)
    return true
end
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Float64}},
    ::Type{CP.DifferentFrom{Float64}},
)
    return true
end

function MOI.get(
    model::Optimizer,
    ::MOI.ListOfConstraintIndices{F, S},
) where {F, S}
    return [
        c.index for
        c in model.constraint_info if typeof(c.f) == F && typeof(c.s) == S
    ]
end

function MOI.get(model::Optimizer, ::MOI.NumberOfConstraints{F, S}) where {F, S}
    count = 0
    for c in model.constraint_info
        if typeof(c.f) == F && typeof(c.s) == S
            count += 1
        end
    end
    return count
end

function MOI.get(model::Optimizer, ::MOI.ListOfConstraints)
    types = Set{Tuple{Any, Any}}()
    for info in model.constraint_info
        push!(types, (typeof(info.f), typeof(info.s)))
    end
    return collect(types)
end
