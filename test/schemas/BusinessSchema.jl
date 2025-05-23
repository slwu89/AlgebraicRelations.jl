module SchemaTest

using Catlab
using Catlab.CategoricalAlgebra
using Catlab.Graphics
using AlgebraicRelations

using Test
using DataFrames
using SQLite
using FunSQL: render, SQLDialect

@present Business(FreeSchema) begin
    (val!Salary, Name)::AttrType
    (Employee, Manager, Income, Salary)::Ob
    name::Attr(Employee, Name)
    #
    (man!employee, man!manager)::Hom(Manager, Employee)
    #
    inc!employee::Hom(Income, Employee)
    inc!salary::Hom(Income, Salary)
    #
    sal!salary::Attr(Salary, val!Salary)
end

busSchema = SQLSchema(Business; types = Dict(:val!Salary => Float64, :Name => String))




@testset "Generate DB Schema" begin
  
for stmt in splt_stmts
    @test execute!(vas, stmt) isa SQLite.Query
end

end

insert_stmts = [
    "INSERT OR IGNORE INTO employee (name, id)   VALUES ('Bob', 1);",
    "INSERT OR IGNORE INTO employee (name, id)   VALUES ('Alice', 2);",
    "INSERT OR IGNORE INTO employee (name, id)   VALUES ('Charlie', 3);",
    "INSERT OR IGNORE INTO employee (name, id)   VALUES ('Eve', 4);",
    "INSERT OR IGNORE INTO manager  (employee, manager, id)    VALUES (1, 1, 1);",
    "INSERT OR IGNORE INTO manager  (employee, manager, id)    VALUES (2, 1, 2);",
    "INSERT OR IGNORE INTO manager  (employee, manager, id)    VALUES (3, 4, 3);",
    "INSERT OR IGNORE INTO manager  (employee, manager, id)    VALUES (4, 1, 4);",
    "INSERT OR IGNORE INTO salary   (salary, id)    VALUES (50000, 1);",
    "INSERT OR IGNORE INTO salary   (salary, id)    VALUES (150000, 2);",
    "INSERT OR IGNORE INTO salary   (salary, id)    VALUES (80000, 3);",
    "INSERT OR IGNORE INTO salary   (salary, id)    VALUES (90000, 4);",
    "INSERT OR IGNORE INTO income   (employee, salary, id)    VALUES (1, 1, 1);",
    "INSERT OR IGNORE INTO income   (employee, salary, id)    VALUES (2, 2, 2);",
    "INSERT OR IGNORE INTO income   (employee, salary, id)    VALUES (3, 3, 3);",
    "INSERT OR IGNORE INTO income   (employee, salary, id)    VALUES (4, 4, 4);"];

for stmt in insert_stmts
    DBInterface.execute(db, stmt)
end

tab = SQLTable(busSchema)

@testset "Generate SQL Queries" begin

  second_level_management = @relation (emp=p, n=n1) begin
    manager(employee=p, manager=m)
    manager(employee=m, manager=m)
    employee(id=p, name=n1)
  end

  asfunsql = to_funsql(second_level_management, busSchema)
  sqlstring = render(asfunsql, dialect=:sqlite) 
  res = DBInterface.execute(db, sqlstring) |> DataFrame
  
  @test ["Bob", "Alice", "Eve"] == res[!,"n"]
  @test [1,2,4] == res[!, "emp"]

  slm = to_funsql(second_level_management, busSchema);

  second_level_income = @relation (salary=s, name=n) begin
    slm(emp = p, n = n)
    income(employee = p, salary = ids)
    salary(id = ids, salary=s)
  end

  asfunsql = to_funsql(second_level_income, busSchema, queries=Dict(:slm => slm))
  sqlstring = render(asfunsql, dialect=:sqlite)
  res = DBInterface.execute(db, sqlstring) |> DataFrame

  @test ["Bob", "Alice", "Eve"] == res[!,"name"]
  @test [50000, 150000, 90000] == res[!, "salary"]

end

end
