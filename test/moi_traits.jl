@testset "Traits" begin
    @testset "is_binary" begin
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variable(model)
        @test !CP.is_binary(model, x)
        @test !CP.is_binary(model, MOI.SingleVariable(x))

        c = MOI.add_constraint(model, x, MOI.ZeroOne())
        @test CP.is_binary(model, x)
        @test CP.is_binary(model, MOI.SingleVariable(x))
    end

    @testset "is_integer" begin
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variable(model)

        @test !CP.is_integer(model, x)
        @test !CP.is_integer(model, MOI.SingleVariable(x))

        c = MOI.add_constraint(model, x, MOI.Integer())
        @test CP.is_integer(model, x)
        @test CP.is_integer(model, MOI.SingleVariable(x))
    end

    @testset "has_lower_bound{$(T)}" for T in [Float64, Int]
        model = MOI.Utilities.Model{T}()
        x = MOI.add_variable(model)
        y = MOI.add_variable(model)
        aff = MOI.ScalarAffineFunction(
            MOI.ScalarAffineTerm.([one(T), zero(T)], [x, y]),
            zero(T), 
        )
        aff2 = MOI.ScalarAffineFunction(
            MOI.ScalarAffineTerm.([one(T), one(T)], [x, y]),
            zero(T), 
        )

        # So far, variables are unbounded.
        @test !CP.has_lower_bound(model, x)
        @test !CP.has_lower_bound(model, MOI.SingleVariable(x))
        @test !CP.has_lower_bound(model, aff)
        @test !CP.has_lower_bound(model, aff2)

        # One variable has a lower bound. 
        MOI.add_constraint(model, x, MOI.GreaterThan(zero(T)))
        @test CP.has_lower_bound(model, x)
        @test CP.has_lower_bound(model, MOI.SingleVariable(x))
        @test CP.has_lower_bound(model, aff) # The other variable has a zero coefficient.
        @test !CP.has_lower_bound(model, aff2)

        # The other variable now has an upper bound: this should not have any 
        # impact on the results.
        MOI.add_constraint(model, y, MOI.LessThan(zero(T)))
        @test CP.has_lower_bound(model, x)
        @test CP.has_lower_bound(model, MOI.SingleVariable(x))
        @test CP.has_lower_bound(model, aff)
        @test !CP.has_lower_bound(model, aff2)
    end

    @testset "has_lower_bound{$(T)}" for T in [Float64, Int]
        model = MOI.Utilities.Model{T}()
        x = MOI.add_variable(model)
        y = MOI.add_variable(model)
        aff = MOI.ScalarAffineFunction(
            MOI.ScalarAffineTerm.([one(T), zero(T)], [x, y]),
            zero(T), 
        )
        aff2 = MOI.ScalarAffineFunction(
            MOI.ScalarAffineTerm.([one(T), one(T)], [x, y]),
            zero(T), 
        )

        # So far, variables are unbounded.
        @test !CP.has_upper_bound(model, x)
        @test !CP.has_upper_bound(model, MOI.SingleVariable(x))
        @test !CP.has_upper_bound(model, aff)
        @test !CP.has_upper_bound(model, aff2)

        # One variable has an upper bound. 
        MOI.add_constraint(model, x, MOI.LessThan(zero(T)))
        @test CP.has_upper_bound(model, x)
        @test CP.has_upper_bound(model, MOI.SingleVariable(x))
        @test CP.has_upper_bound(model, aff) # The other variable has a zero coefficient.
        @test !CP.has_upper_bound(model, aff2)

        # The other variable now has a lower bound: this should not have any 
        # impact on the results.
        MOI.add_constraint(model, y, MOI.GreaterThan(zero(T)))
        @test CP.has_upper_bound(model, x)
        @test CP.has_upper_bound(model, MOI.SingleVariable(x))
        @test CP.has_upper_bound(model, aff)
        @test !CP.has_upper_bound(model, aff2)
    end
end
