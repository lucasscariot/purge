let a = [["a", "b"], ["c", "d"]]
let b = [["e", "f"]]
struct Obj { let sets: [[String]] }
let objs = [Obj(sets: a), Obj(sets: b)]
let result = objs.flatMap { $0.sets }
print(result)
