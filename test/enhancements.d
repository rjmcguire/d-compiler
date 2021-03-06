// (code taken from dlang changelog)

struct SlicingSyntax{
	static call(const(char)* str) { }
	static main(){
		const(char)* abc = "abc";
		call(abc);
		
		const(char)* ab = "abc"[0 .. 2];
		call(ab);
	}
}

/+struct A
{
    struct Foo { }
}

struct B
{
    struct Foo { }
}

void call(T)(T t, T.Foo foo) { } // TODO: do not show an error

void main()
{
    auto a = A();
    auto a_f = A.Foo();
    call(a, a_f);

    auto b = B();
    auto b_f = B.Foo();
    call(b, b_f);
    call(a, b_f); // error
}
+/