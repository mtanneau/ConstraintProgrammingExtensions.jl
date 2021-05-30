using MathOptInterface, ConstraintProgrammingExtensions

using Test

const CP = ConstraintProgrammingExtensions
const COIT = CP.Test
const COIB = CP.Bridges
const MOI = MathOptInterface
const MOIB = MOI.Bridges
const MOIT = MOI.Test
const MOIU = MOI.Utilities

include("Bridges/models.jl")

@testset "ConstraintProgrammingExtensions" begin
    # include("sets.jl")
    # include("moi_traits.jl")
    # include("moi_fcts.jl")
    include("Bridges/Bridges.jl")
    # include("FlatZinc/FlatZinc.jl")
    # include("Test/Test.jl")
end
