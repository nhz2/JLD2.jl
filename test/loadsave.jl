using JLD2, FileIO, Test

fn = joinpath(mktempdir(), "test.jld2")

# Test load macros
jldopen(fn, "w") do f
    write(f, "loadmacrotestvar1", ['a', 'b', 'c'])
    write(f, "loadmacrotestvar2", 1)
end

@eval begin # wrapped in eval since @load with no args needs file at compile time
function func1()
    @load $fn
    @test loadmacrotestvar1 == ['a', 'b', 'c']
    @test loadmacrotestvar2 == 1
end
end

func1()

function func2()
    @load fn loadmacrotestvar1 loadmacrotestvar2
    @test loadmacrotestvar1 == ['a', 'b', 'c']
    @test loadmacrotestvar2 == 1
end

func2()

@test !isdefined(@__MODULE__, :loadmacrotestvar1) # should not be in global scope
@test (@eval @load $fn) == [:loadmacrotestvar1, :loadmacrotestvar2]
@test loadmacrotestvar1 == ['a', 'b', 'c']
@test loadmacrotestvar2 == 1

# Test save macros
hello = "world"
@save fn hello
jldopen(fn, "r") do f
    @test read(f, "hello") == "world"
end

cmd = """
using JLD2
hello = "there"
@save $(repr(fn))
"""
run(`$(Base.julia_cmd()) -e $cmd`)
jldopen(fn, "r") do f
    @test read(f, "hello") == "there"
end

# Test Dict save/load
save(format"JLD2", fn, Dict("the"=>"quick", "brown"=>"fox", "stuff"=>reshape(1:4, (2, 2))))
@test load(fn) == Dict("the"=>"quick", "brown"=>"fox", "stuff"=>reshape(1:4, (2, 2)))

# Test load/save with pairs
save(format"JLD2", fn, "jumps", "over", "the", "lazy", "dog", reshape(1:4, (2, 2)))
@test load(fn, "jumps", "the", "dog") == ("over", "lazy", reshape(1:4, (2, 2)))
@test load(fn, "jumps") == "over"

jldopen(fn, "r+") do f
    @test !isempty(f)
    @test haskey(f, "dog")
    @test !haskey(f, "notdog")
    @test keys(f) == ["jumps", "the", "dog"]
    x1 = rand(UInt8, 1024^2+1024)
    x2 = rand(UInt8, 1024)
    f["x1"] = x1
    f["x2"] = x2
    @test f["x1"] == x1
    @test f["x2"] == x2
end

# Issue #19
save(fn, Dict("a"=>[1,2,3]))
io = open(fn)
@info("The next error message (involving \"loading nothing\") is a sign of normal operation")
@test_throws MethodError load(io)
close(io)

# Issue #33
d = Dict("params/p1" => 1,
         "params/p2" => 2.,
         "params/p3/p1" => 94,
         "data" => [[1,2,3], [4.,5.,6]])
save(fn, d)
@test load(fn) == d

# Issue #106
mutable struct MyMutableTest
    a::Int
    b::Vector{Int}
end
Base.getproperty(df::MyMutableTest, s::Symbol) =
    throw(ArgumentError("should not be called"))
Base.setproperty!(df::MyMutableTest, s::Symbol, x::Int) =
    throw(ArgumentError("should not be called"))
Base.isequal(x::MyMutableTest, y::MyMutableTest) =
    isequal(getfield(x, :a), getfield(y, :a)) && isequal(getfield(x, :b), getfield(y, :b))
mmtd = Dict("A" => MyMutableTest(1, [10]))
save(fn, mmtd)
@test isequal(load(fn), mmtd)

# Issue #125
len = 2^16
longstring = prod(fill("*",len));
lsd = Dict("longstring" => longstring)
save(fn, lsd)
@test isequal(load(fn), lsd)

# Issue #131
# write/read a Union{T,Missing}
len = 10_000
vect = Vector{Union{Bool,Missing}}(undef,len)
vect .= true
jldopen(fn,"w") do f
  f["vect"] = vect
end
vect_read = jldopen(fn,"r") do f
  f["vect"]
end
@test !any(ismissing.(vect_read))

# Also related to issue #131, but more types
len = 10_000
vect = Vector{Union{Missing,Float32,Float64,Int32}}(missing,len)
vect[vcat(1:10,33,44,55)] .= Int32(21)
vect[vcat(11:20,66,77,88)] .= 33.
vect[vcat(21:30,99)] .= Float32(123.)
jldopen(fn,"w") do f
  f["vect"] = vect
end
vect_read = jldopen(fn,"r") do f
  f["vect"]
end
@test all(findall(ismissing,vect) == findall(ismissing,vect_read))
@test all( skipmissing(vect) .=== skipmissing(vect_read))
