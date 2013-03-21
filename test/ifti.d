
auto exec(T)(T arg){
	pragma(msg, T);
	return arg();
}
pragma(msg, exec((int x=2)=>x));// TODO: strip default params
pragma(msg, exec((int x=3)=>x));



/+// TODO: should this work?
string myAssert(Args...)(lazy bool condition, lazy Args args, int line = 12, string file = "file.d"){
	if(!condition) return "Assertion failed @ "~file~":"~toString(line)~"\n"~args[0];
	return "";
}
pragma(msg, myAssert(false, "hello"));+/


/+// TODO: should this work?
bool queueDG(S,T,R=T)(S x, R delegate(T) delegate(S) dg, T y){
	return dg(x)(y);
}
pragma(msg, "queueDG: ", queueDG(2, a=>b=>b&&a==2,true));+/


template FooDg(Z,A,B...) { alias Delegate!(Z,A) delegate(B) FooDg; }

bool instFooDg(S,T,R=T)(S x, FooDg!(T,T,S) dg, T y){ // TODO: why does FooDg!(R,T,S) not work?
	return dg(x)(y);
}
pragma(msg, "instFooDg: ", instFooDg(2, a=>b=>b&&a==2,true));


template ElementType(T){ alias typeof({T t; return t[0];}()) ElementType; } // display e

template Seq(T...){ alias T Seq; }
template Delegate(R,T...){ alias Seq!(R, R)[1] delegate(Seq!T) Delegate; }

void transform(IR,OR,I=ElementType!IR,O)(IR input, OR output, scope Delegate!(O,I) dg){
//void transform(IR,OR,O)(IR input, OR output, scope O delegate(ElementType!IR) dg){
	for(auto i = input.length-input.length; i<input.length; i++)
		output[i] = dg(input[i]);
}
	
pragma(msg, "transform: ",{
	auto a = [1,2,3];
	auto r = [0,0,0];
	transform(a,r,a=>a+1);
	return r;
}());

template MAlias(A,B){ alias A delegate(B) MAlias; }

auto malias(A,B)(MAlias!(A,B) dg, B arg){ return dg(arg); }
pragma(msg, malias((int x)=>x,3));

auto combine(T)(T a, T b, T c){return [a,b,c];}

pragma(msg, "combine: ", combine([],[],[1,2,3]));
pragma(msg, "typeof(combine): ",typeof(combine([],[],[1,2,3])));


auto nomatch(T,S,R)(T t, S s, R r){ return t; }
pragma(msg, nomatch!int(1.0,2,"3")); // error



template tmpl(T){
	static if(is(T==double)){
		T[] tmpl(T arg){return [arg, 2*arg];}
	}else{
		T[] tmpl(T arg){return is(T==int)?[arg]:[arg,arg,2*arg];}
	}
	//alias int T;
}
pragma(msg, "tmpl!int: ",tmpl!int(2),"\ntmpl!float: ",tmpl!float(2),"\ntmpl!double",tmpl!double(2),"\ntmpl!real: ",tmpl!real(22));

auto potentiallyambiguous3(R,A...)(R delegate(A) a, R delegate(A) b){}
pragma(msg, potentiallyambiguous3!()(y=>2.0*y, (long z)=>z/2)); // error (TODO: should it work?)

auto potentiallyambiguous2(R)(R delegate(int) a, R b){
	pragma(msg,"notambiguous21R: ", R);
	return true;
}
pragma(msg, "notambiguous2: ",potentiallyambiguous2!()(x=>1.0,1));


auto potentiallyambiguous(R)(R delegate(int) a, R delegate(int) b){
	pragma(msg,"notambiguousR: ", R);
	return true;
}
immutable string mxinx = "x";
pragma(msg, potentiallyambiguous!()(x=>toString(x), x=>mixin(mxinx))); // error. TODO: show it!
pragma(msg, "notambiguous: ",potentiallyambiguous!()(x=>1.0,x=>1.0L));

auto qux(S,T...)(S s, T arg){
	pragma(msg, S, " ", T);
	return s+arg.length;
}

//pragma(msg, qux!(int)(2,"1",1.0));

template deducetwotuples(R){
	R deducetwotuples(T1...,T2...)(R delegate(T1) dg1, R delegate(T2) dg2){
		pragma(msg, T1," ",T2);
		return dg1(StaticIota!(1,T1.length+1))~" "~dg2(StaticIota!(1,T2.length+1));
	}
}
pragma(msg, (deducetwotuples!string)!(int,double,float)((int x, double y, float z)=>toString(x), (int y, int x)=>toString(x)~" "~toString(y)));


template TypeTuple(T...){ alias T TypeTuple; }
template StaticIota(int a, int b) if(a<=b){
	static if(a==b) alias TypeTuple!() StaticIota;
	else alias TypeTuple!(a,StaticIota!(a+1,b)) StaticIota;
}

template StaticAll(string _pred, _A...){
	static if(!_A.length) enum StaticAll = true;
	else{
		alias _A[0] a;
		enum StaticAll = mixin(_pred) && StaticAll!(_pred,_A[1..$]);
	}
}

auto exec(R,A1,A...)(R delegate(A1,A) dg) if(is(A1==int) && StaticAll!("is(a:int)",A)){
	return dg(StaticIota!(1,A.length+2));
}

pragma(msg, exec!()((int x,short y)=>toString(x)~" "~toString(y)));
pragma(msg, exec!()((int x,short y,byte z)=>toString(x)~" "~toString(y)~" "~toString(z)));

pragma(msg, mixin(exec!()((int x,short y,byte z)=>toString(x)~"+"~toString(y)~"*"~toString(z))));

pragma(msg, exec!()((int x,int y,int z)=>toString(x)~" "~toString(y)~" "~toString(z)));


static assert(mixin(exec!()((int x,short y,byte z)=>toString(x)~"+"~toString(y)~"*"~toString(z)))==7);


//auto foo()(int a, int b){return a;}
//pragma(msg, foo!()(1));

auto inexistentparamtype(T...)(S arg){ }
auto inexistentparamtype(T...)(S arg) if(T.length){ // TODO: gag
	return arg.length;
}
pragma(msg, inexistentparamtype!()(2));

bool all(alias a,T)(T[] r){
	pragma(msg, typeof(a!int));
	for(typeof(r.length) i=0;i<r.length;i++)
		if(!a!()(r[i])) return false;
	return true;
}

pragma(msg, "all: ",all!(x=>x&1)([1,3,4,5]));



//T identity(T)(const arg=2) {pragma(msg,T," ",typeof(arg)); return arg; }
T identity(T)(const T arg) {pragma(msg,T," ",typeof(arg)); return arg; }

template NotAFunctionTemplate(){void foo(){}}

//pragma(msg, NotAFunctionTemplate());


pragma(msg, identity!(ulong)(12));
pragma(msg, identity!()(cast(const)1)," ",identity!()("string")," ",identity!()(3.0));

T[] filter(T)(T[] a, bool delegate(T) f){
	T[] r;
	for(int i=0;i<a.length;i++) r~=f(a[i])?[a[i]]:[];
	return r;
}

pragma(msg, filter!()([1,2,3,4,5],x=>x&1));

S[] map(T,S)(T[] a, S delegate(T) f){
	S[] r;
	for(int i=0;i<a.length;i++) r~=f(a[i]);
	return r;
}

//pragma(msg, map!()([1,2,3,4,5],(float x)=>x+2.0));

immutable int y = 2;
pragma(msg, map!()([1,2,3],x=>x+y));

pragma(msg, map!()([1,2,3,4,5], x=>x+2));


R[] map2(T,S,R)(const(T)[] a, S delegate(T) f, R delegate(S) g){
	pragma(msg,"typeof(a): ",typeof(a));
	R[] r;
	for(int i=0;i<a.length;i++) r~=g(f(a[i]));
	return r;
}
immutable(float[]) fa = [1,2,3,4];
pragma(msg, map2!()(fa,x=>cast(int)x*1020304,x=>toString(x)));

/+ TODO: should this work?
int test(int delegate(int) dg){
	return dg(2);
}
int test2(alias a)(){ return test(&a); }

pragma(msg, test2!(x=>x)());+/

//T idint(T: int)(T arg){ return arg;}
//pragma(msg, idint!()(1.0); // error
//T idfloat(T : float)(T arg){ return arg;}
//pragma(msg, idfloat!()(1.0));


// +/
alias immutable(char)[] string;

auto toString(int i){
	immutable(char)[] s;
	do s=(i%10+'0')~s, i/=10; while(i);
	return s;
}
