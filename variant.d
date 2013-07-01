// Written in the D programming language.

import lexer, operators, expression, declaration, type, semantic, util;

import std.algorithm: map;
import std.traits: isIntegral, isFloatingPoint, Unqual;
import std.range: ElementType;
import std.conv: to;
import std.string : text;

import std.stdio;

// TODO: refactor the whole code base into smaller modules
struct BCSlice{
	void[] container;
	void[] slice;

	this(void[] va){
		container = slice = va;
	}
	this(void[] cnt, void[] slc){
		container = cnt;
		slice = slc;
	}

	BCPointer getPtr(){
		return BCPointer(container, slice.ptr);
	}
	size_t getLength(){
		return slice.length;
	}

	void setLength(size_t len){
		slice.length = len;
		if(slice.ptr<container.ptr||slice.ptr>=container.ptr+container.length)
			container = slice;
	}
}

struct BCPointer{
	void[] container;
	void* ptr;
}

enum Occupies{
	none, str, wstr, dstr, int64, flt80, fli80, cmp80, arr, ptr_, vars, err
}

template getOccupied(T){
	static if(is(T==string))
		enum getOccupied = Occupies.str;
	else static if(is(T==wstring))
		enum getOccupied = Occupies.wstr;
	else static if(is(T==dstring)){
		enum getOccupied = Occupies.dstr;
	}else static if(is(T:long)&&!is(T==struct)&&!is(T==class))
		enum getOccupied = Occupies.int64;
	else static if(isFloatingPoint!T){
		static assert(T.sizeof<=typeof(Variant.flt80).sizeof);
		enum getOccupied = Occupies.flt80;	
	}else static if(is(T==ifloat)||is(T==idouble)||is(T==ireal))
		enum getOccupied = Occupies.fli80;
	else static if(is(T==cfloat)||is(T==cdouble)||is(T==creal))
		enum getOccupied = Occupies.cmp80;
	else static if(is(T==Variant[]))
		enum getOccupied = Occupies.arr;
	else static if(is(T==Variant*))
		enum getOccupied = Occupies.ptr_;
	else static if(is(T==typeof(null)))
		enum getOccupied = Occupies.none;
	else static if(is(T==Variant[VarDecl]))
		enum getOccupied = Occupies.vars;
	else static assert(0);
}

private bool occString(Occupies occ){
	static assert(Occupies.str+1 == Occupies.wstr && Occupies.wstr+1 == Occupies.dstr);
	return occ >= Occupies.str && occ <= Occupies.dstr;
}

/+
template FullyUnqual(T){
	static if(is(T _:U[], U)) alias FullyUnqual!U[] FullyUnqual;
	else static if(is(T _:U*, U)) alias FullyUnqual!U* FullyUnqual;
	else alias Unqual!T FullyUnqual;
}+/

/+
private struct WithLoc(T){
	T payload;
	// TODO: this can be represented in a smarter way
	Location[] locs;
	this(T pl, Location[] lcs){payload = pl; locs=lcs;}
	this(T pl, Location loc){payload = pl; locs=[loc];}

	WithLoc opBinary(op: "~")(WithLoc rhs){
		return WithLoc(payload~rhs.payload, locs~rhs.locs);
	}

	WithLoc opIndex(
}
+/

struct FieldAccess{
	@property isIndex(){ return _isindex; }
	@property index()in{assert(isIndex);}body{ return _index; }
	@property field()in{assert(!isIndex);}body{ return _field; }

	this(size_t index){
		this._index = index;
		_isindex = true;
	}

	this(VarDecl field)in{assert(field.isField);}body{
		this._field = field;
		_isindex = false;
	}

	string toString(){
		if(isIndex) return "["~index.to!string~"]";
		return "."~field.name.to!string;
	}

private:
	union{
		size_t _index;
		VarDecl _field;
	}
	bool _isindex;
}

struct Variant{
	private Type type;
	private @property Occupies occupies(){
		// TODO: this is probably too slow
		// TODO: cache inside type?
		if(!type) return Occupies.vars;		
		auto tu=type.getHeadUnqual();
		if(tu.isAggregateTy()) return Occupies.vars;
		if(tu is Type.get!string()) return Occupies.str;
		if(tu is Type.get!wstring()) return Occupies.wstr;
		if(tu is Type.get!dstring()) return Occupies.dstr;
		if(tu.getElementType()) return Occupies.arr;
		if(tu.isPointerTy()) return Occupies.ptr_;

		if(auto bt=tu.isBasicType()){
			switch(bt.op){
				foreach(x;ToTuple!basicTypes){
					static if(x!="void")
					case Tok!x:
						mixin("alias "~x~" T;"); // workaround DMD bug
						return getOccupied!T;
				}
				default: assert(0);
			}
		}

		
		assert(tu is Type.get!(typeof(null)), tu.text);
		return Occupies.none;
	}

	this(T)(T value, Type type)if(!is(T==Variant[])&&!is(T==Variant[VarDecl]))in{
		assert(type.sstate==SemState.completed);
		// TODO: suitable in contract for type based on T
	}body{
		//type = Type.get!T();
		this.type = type;
		mixin(to!string(getOccupied!T)~` = value;`);
	}

	this()(Variant[] arr, Variant[] cnt, Type type)in{
		assert(type.getElementType(),text(type));
		auto tt=type.getElementType().getUnqual(); // TODO: more restrictive assertion desirable
		if(tt !is Type.get!(void*)()&&tt!is Type.get!(void[])())
			foreach(x;cnt) assert(tt is x.type.getUnqual(),text(cnt," ",tt," ",x.type," ",x));
	}body{
		this.type=type;
		this.arr=arr;
		this.cnt=cnt;
	}

	this()(FieldAccess[] ptr, Variant[] cnt, Type type)in{
		auto pt=type.isPointerTy();
		assert(!!pt);
		auto tt=pt.ty.getUnqual();

		if(tt !is Type.get!(void*)()&&tt!is Type.get!(void[])())
			foreach(x;cnt) assert(tt is x.type.getUnqual());
	}body{
		this.type=type;
		this.ptr_=ptr;
		this.cnt=cnt;
	}

	this()(Variant[VarDecl] vars, Type type = null){ // templated because of DMD bug
		//id = RTTypeID.get!Vars(type);
		this.type=type;
		this.vars=vars;
	}


	private union{
		typeof(null) none;
		string str; wstring wstr; dstring dstr;
		ulong int64;
		real flt80; ireal fli80; creal cmp80;
		struct{
			union{
				Variant[] arr;
				FieldAccess[] ptr_;
			}
			Variant[] cnt;
			Variant[VarDecl] ptrvars;
			VarDecl ptrvd;
		}
		Variant[VarDecl] vars; // structs, classes, closures
		string err;
	}

	T get(T)(){
		static if(is(T==string)){
			if(occupies == Occupies.str) return str;
			else if(occupies == Occupies.wstr) return to!string(wstr);
			else if(occupies == Occupies.dstr) return to!string(dstr);
			else return toString();
		}
		else static if(is(T==wstring)){assert(occupies == Occupies.wstr); return wstr;}
		else static if(is(T==dstring)){assert(occupies == Occupies.dstr); return dstr;}
		else static if(getOccupied!T==Occupies.int64){assert(occupies == Occupies.int64,"occupies was "~to!string(occupies)~" instead of int64"); return cast(T)int64;}
		else static if(is(T==float)||is(T==double)||is(T==real)){
			assert(occupies == Occupies.flt80||occupies == Occupies.fli80);
			return flt80;
		}else static if(is(T==ifloat) || is(T==idouble)||is(T==ireal)){
			assert(occupies == Occupies.fli80);
			return fli80;
		}else static if(is(T==cfloat) || is(T==cdouble)||is(T==creal)){
			assert(occupies == Occupies.cmp80);
			return cmp80;
		}else static if(is(T==Variant[VarDecl])){
			if(occupies == Occupies.none) return null;
			assert(occupies == Occupies.vars,text(occupies));
			return vars;
		}else static if(is(T==Variant[])){
			assert(occupies == Occupies.arr);
			return arr;
		}else static assert(0, "cannot get this field (yet?)");
	}

	Variant[] getContainer()in{
		assert(occupies == Occupies.arr||occupies == Occupies.ptr_);
	}body{
		return cnt;
	}

	/* returns a type that fully specifies the memory layout
	   for strings, the relevant type qualifiers are preserved
	   otherwise, gives no guarantees for type qualifier preservation
	 */

	Type getType()out{assert(!type||type.sstate==SemState.completed);}body{
		return type;
	}

	Expression toExpr(){
		if(type){
			auto r = LiteralExp.factory(this);
			r.semantic(null);
			return r;
		}else return New!ErrorExp();
	}

	string toString(){
		if(!type){
			assert(occupies==Occupies.vars);
			return to!string(vars);
		}
		auto type=type.getHeadUnqual();
		if(type is Type.get!(typeof(null))()) return "null";
		if(type.isSomeString()){
			foreach(T;Seq!(string,wstring,dstring)){
				if(type !is Type.get!T()) continue;
				enum occ = getOccupied!T;
				enum sfx = is(T==string)  ? "c" :
					       is(T==wstring) ? "w" :
						   is(T==dstring) ? "d" : "";
				return to!string('"'~escape(mixin(`this.`~to!string(occ)))~'"'~sfx);
			}
		}
		if(auto bt=type.isBasicType()){
			switch(bt.op){
				foreach(x;ToTuple!basicTypes){
					static if(x!="void")
					case Tok!x:
						mixin(`alias typeof(`~x~`.init) T;`); // dmd parser workaround
						enum sfx = is(T==uint) ? "U" :
					       is(T==long)||is(T==real) ? "L" :
						   is(T==ulong) ? "LU" :
						   is(T==float) ? "f" :
				           is(T==ifloat) ? "fi" :
					       is(T==idouble) ? "i" :
						   is(T==ireal) ? "Li":"";
						enum left = is(T==char)||is(T==wchar)||is(T==dchar) ? "'" : "";
						enum right = left;
						// remove redundant "i" from imaginary literals
						enum oc1 = getOccupied!T;
						enum occ = oc1==Occupies.fli80?Occupies.flt80:oc1;
						
						string rlsfx = ""; // TODO: extract into its own function?
						string res = to!string(mixin(`cast(T)this.`~to!string(occ)));
						static if(occ==Occupies.flt80)
							if(this.flt80%1==0&&!res.canFind("e")) rlsfx=".0";
						return left~res~right~rlsfx~sfx;						
				}
				default: assert(0);
			}
		}
		if(type.getElementType()){
			import std.algorithm, std.array;
			return '['~join(map!(to!string)(this.arr),",")~']';
		}
		if(type.isPointerTy()){
			return "&("~ptr_.map!(to!string).join~")"; // TODO: fix
		}
		if(type.isAggregateTy()){
			if(this.vars is null) return "null";
			return this.type.toString(); // TODO: pick up toString?
		}
		assert(0,"cannot get string");
	}

	Variant convertTo(Type to)in{assert(!!type);}body{
		if(to is type) return this;
		auto type = getType().getHeadUnqual();
		auto tou = to.getHeadUnqual();
		if(type is Type.get!(typeof(null))()){
			if(tou is Type.get!(typeof(null))()) return this;
			if(tou.getElementType()) return Variant((Variant[]).init,(Variant[]).init,to);
			if(tou.isAggregateTy()) return Variant((Variant[VarDecl]).init, to);
			// TODO: null pointers and delegates
			assert(0,"cannot convert");
		}else if(type.isSomeString()){
			foreach(T;Seq!(string,wstring,dstring)){
				enum occ=getOccupied!T;
				if(type !is Type.get!T()) continue;
				if(tou is Type.get!string())
					return Variant(.to!string(mixin(`this.`~.to!string(occ))),to);
				else if(tou is Type.get!wstring())
					return Variant(.to!wstring(mixin(`this.`~.to!string(occ))),to);
				else if(tou is Type.get!dstring())
					return Variant(.to!dstring(mixin(`this.`~.to!string(occ))),to);
				else if(auto ety2=tou.getElementType()){
					// TODO: revise allocation
					auto r = new Variant[this.length];
					foreach(i,x;mixin(`this.`~.to!string(occ))) r[i]=Variant(x,ety2);
					return Variant(r,r,to);//TODO: aliasing?
				}
				return this; // TODO: this is a hack and might break stuff (?)
				break;
			}
		}else if(auto tbt=type.isBasicType()){
			if(auto bt = tou.isBasicType()){
				switch(tbt.op){
					foreach(tx;ToTuple!basicTypes){
						static if(tx!="void"){
							case Tok!tx:// TODO: code generated for integral types is identical
							mixin(`alias typeof(`~tx~`.init) T;`); // dmd parser workaround
							enum occ=getOccupied!T;
							switch(bt.op){
								foreach(x;ToTuple!basicTypes){
									static if(x!="void")
									case Tok!x:
										return Variant(mixin(`cast(`~x~`)cast(T)this.`~.to!string(occ)),to);
								}
								case Tok!"void": return this;
								default: assert(0);
							}
						}
					}
					default: assert(0);
				}
			}
		}else if(type.isDynArrTy()){
			// assert(to.getHeadUnqual().getElementType()!is null);
			if(tou is Type.get!string()){
				string s;
				foreach(x; this.arr) s~=cast(char)x.int64;
				return Variant(s,to);
			}else if(tou is Type.get!wstring()){
				wstring s;
				foreach(x; this.arr) s~=cast(wchar)x.int64;
				return Variant(s,to);
			}else if(tou is Type.get!dstring()){
				dstring s;
				foreach(x; this.arr) s~=cast(wchar)x.int64;
				return Variant(s,to);
			}
			// TODO: Sanity check?
			if(tou.getUnqual() is Type.get!(void[])()) return this;
			return Variant(arr,cnt,to);
		}else if(type is Type.get!EmptyArray()){
			assert(tou.isDynArrTy()||tou.isArrayTy()&&tou.isArrayTy().length==0);
			if(tou.isSomeString()){
				foreach(T;Seq!(string,wstring,dstring))
					if(tou is Type.get!T()) return Variant(T.init/+,T.init+/,to);
			}
			return Variant((Variant[]).init,(Variant[]).init,to);
		}
		return this;
	}

	bool opCast(T)()if(is(T==bool)){
		assert(type == Type.get!bool(), to!string(type)~" "~toString());
		return cast(bool)int64;
	}

	private Variant strToArr()in{
		assert(occString(occupies));
	}body{ // TODO: get rid of this
		Variant[] r = new Variant[length];
		auto elt=type.getElementType().getUnqual(); // TODO: should this be const sometimes?
		theswitch:switch(occupies){
			foreach(occ;ToTuple!([Occupies.str, Occupies.wstr, Occupies.dstr])){
				case occ:
					foreach(i,x; mixin(to!string(occ))) r[i] = Variant(x,elt);
					break theswitch;
			}
			default: assert(0);
		}
		return Variant(r,r,elt.getDynArr());
	}

	bool opEquals(Variant rhs){ return cast(bool)opBinary!"=="(rhs); }

	size_t toHash()@trusted{
		final switch(occupies){
			case Occupies.none: return 0;
				foreach(x; EnumMembers!Occupies[1..$]){
					case x: return typeid(mixin(to!string(x))).getHash(&mixin(to!string(x)));
				}
		}
		assert(0); // TODO: file bug
	}

	// TODO: BUG: shift ops not entirely correct
	Variant opBinary(string op)(Variant rhs)in{
		static if(isShiftOp(Tok!op)){
			assert(occupies == Occupies.int64 && rhs.occupies == Occupies.int64);
		}else{
			//assert(occupies == Occupies.arr || id.whichBasicType!=Tok!"" && id.whichBasicType == rhs.id.whichBasicType,
			//       to!string(id.whichBasicType)~"!="~to!string(rhs.id.whichBasicType));
			assert(occupies == rhs.occupies
			    || occupies == Occupies.arr && occString(rhs.occupies)
			    || rhs.occupies == Occupies.arr && occString(occupies)
			    || op == "%" && occupies == Occupies.cmp80 &&
			       (rhs.occupies == Occupies.flt80 || rhs.occupies == Occupies.fli80),
			       to!string(this)~" is incompatible with "~
			       to!string(rhs)~" in binary '"~op~"' expression");
		}
	}body{
		if(occupies == Occupies.arr){
			if(rhs.occupies != Occupies.arr) rhs=rhs.strToArr();
			static if(op=="~"){
				auto r=arr~rhs.arr;
				return Variant(r,r,type);
			}static if(op=="is"||op=="!is"){
				return Variant(mixin(`arr `~op~` rhs.arr`),Type.get!bool());
			}static if(op=="in"||op=="!in"){
				// TODO: implement this
				assert(0,"TODO");
			}else static if(isRelationalOp(Tok!op)){
				// TODO: create these as templates instead
				auto l1 = length, l2=rhs.length;
				static if(op=="=="){if(l1!=l2) return Variant(false,Type.get!bool());}
				else static if(op=="!=") if(l1!=l2) return Variant(true,Type.get!bool());
				if(l1&&l2){
					auto tyd = arr[0].type.combine(rhs.arr[0].type);
					assert(!tyd.dependee);// should still be ok though.
					Type ty = tyd.value;
					foreach(i,v; arr[0..l1<l2?l1:l2]){
						auto l = v.convertTo(ty), r = rhs.arr[i].convertTo(ty);
						if(l.opBinary!"=="(r)) continue;
						else{
							static if(op=="==") return Variant(false,Type.get!bool());
							else static if(op=="!=") return Variant(true,Type.get!bool());
							else return l.opBinary!op(r);
						}
					}
				}
				// for ==, != we know that the lengths must be equal
				static if(op=="==") return Variant(true,Type.get!bool());
				else static if(op=="!=") return Variant(false,Type.get!bool());
				else return Variant(mixin(`l1 `~op~` l2`),Type.get!bool());
			}
		}else if(occupies == Occupies.ptr_){
			assert(rhs.occupies==Occupies.ptr_);
			// TODO: other relational operators
			static if(op=="is"||op=="=="||op=="!is"||op=="!="){
				return Variant((op=="!is"||op=="!=")^(ptr_ is rhs.ptr_),Type.get!bool());
			}else assert(0);
		}else if(occupies == Occupies.vars){
			assert(rhs.occupies==Occupies.vars);
			assert(!!type && type.getHeadUnqual().isAggregateTy() && type.getHeadUnqual().isAggregateTy().decl.isClassDecl());
			static if(op=="is"||op=="!is")
				return Variant((op=="!is")^(vars is rhs.vars),Type.get!bool());
			else assert(0);
		}else if(occupies == Occupies.none){
			static if(is(typeof(mixin(`null `~op~` null`))))
				return Variant(mixin(`null `~op~` null`),
				         Type.get!(typeof(mixin(`null `~op~` null`)))());
			else assert(0);
		}

		if(type.getHeadUnqual().isSomeString()){
			foreach(x; ToTuple!(["``c","``w","``d"])){
				alias typeof(mixin(x)) T;
				alias getOccupied!T occ;
				assert(occupies == occ);
				enum code = to!string(occ)~` `~op~` rhs.`~to!string(occ);
				static if(op!="-" && op!="+" && op!="<>=" && op!="!<>=") // DMD bug
				static if(is(typeof(mixin(code)))){
					if(type.getHeadUnqual() is Type.get!(typeof(mixin(x)))()){ 
						if(rhs.occupies == occupies)
							return Variant(mixin(code),Type.get!(typeof(mixin(code)))());
						else return strToArr().opBinary!op(rhs);
					}
				}
			}
		}

		assert(cast(BasicType)type.getHeadUnqual(),text(type));
		switch((cast(BasicType)cast(void*)type.getHeadUnqual()).op){
			foreach(x; ToTuple!basicTypes){
				static if(x!="void"){
					alias typeof(mixin(x~`.init`)) T;
					alias getOccupied!T occ;
					static if(occ == Occupies.cmp80 && op == "%")
						// can do complex modulo real
						// relies on same representation for flt and fli
						enum occ2 = Occupies.flt80;
					else enum occ2 = occ;
					assert(occupies == occ);
					//assert(rhs.occupies == occ2);
					static if(isShiftOp(Tok!op)|| occ2 != occ) enum cst = ``;
					else enum cst = q{ cast(T) };
					enum code = q{
						mixin(`cast(T)` ~ to!string(occ) ~` `~ op ~ cst~`rhs.` ~ to!string(occ2))
					};
					static if(is(typeof(mixin(code))))
						case Tok!x: return Variant(mixin(code),Type.get!(typeof(mixin(code)))());
				}
			}
			default: break;
		}
		assert(0, "no binary '"~op~"' support for "~type.toString());
	}
	Variant opUnary(string op)(){
		assert(cast(BasicType)type.getHeadUnqual());
		switch((cast(BasicType)cast(void*)type.getHeadUnqual()).op){
			foreach(x; ToTuple!basicTypes){
				static if(x!="void"){
					alias typeof(mixin(x~`.init`)) T;
					alias getOccupied!T occ;
					enum code = q{ mixin(op~`cast(T)`~to!string(occ)) };
					static if(is(typeof(mixin(code))==T))
					case Tok!x: return Variant(mixin(code), Type.get!T());
				}
			}
			default: assert(0, "no unary '"~op~"' support for "~type.toString());
		}
	}

	@property Variant ptr()in{
		assert(occupies==Occupies.arr); // TODO: pointers to string
	}body{
		return Variant([FieldAccess(arr.ptr-cnt.ptr)], cnt, type.getElementType().getPointer());
	}

	@property size_t length()in{
		assert(occupies==Occupies.arr||occupies == Occupies.str
		       || occupies == Occupies.wstr || occupies == Occupies.dstr);
	}body{
		if(occupies == Occupies.arr) return arr.length;
		else switch(occupies){
			foreach(x; ToTuple!(["str","wstr","dstr"])){
				case mixin(`Occupies.`~x): return mixin(x).length;
			}
			default: assert(0);
		}
	}

	FieldAccess[] getFieldAccess()in{
		assert(occupies==Occupies.ptr_);
	}body{
		return ptr_;
	}



	Variant opIndex(Variant index)in{
		assert(index.occupies==Occupies.int64);
		assert(occupies == Occupies.arr||occupies == Occupies.str
		       || occupies == Occupies.wstr || occupies == Occupies.dstr);
	}body{
		if(occupies == Occupies.arr){
			assert(index.int64<arr.length, to!string(index.int64)~">="~to!string(arr.length));
			return arr[cast(size_t)index.int64];
		}else switch(occupies){
			foreach(x; ToTuple!(["str","wstr","dstr"])){
				case mixin(`Occupies.`~x):
					assert(index.int64<mixin(x).length);
					return Variant(mixin(x)[cast(size_t)index.int64], Type.get!(ElementType!(typeof(mixin(x)))));
			}
			default: assert(0);
		}
	}
	Variant opIndex(size_t index){
		return this[Variant(index,Type.get!Size_t())];
	}

	Variant opSlice(Variant l, Variant r)in{
		assert(l.occupies==Occupies.int64);
		assert(occupies == Occupies.arr||occupies == Occupies.str
		       || occupies == Occupies.wstr || occupies == Occupies.dstr);
	}body{
		if(occupies == Occupies.arr){
			assert(l.int64<=arr.length && r.int64<=arr.length);
			assert(l.int64<=r.int64);
			return Variant(arr[cast(size_t)l.int64..cast(size_t)r.int64],cnt,type.getElementType().getDynArr()); // aliasing ok?
		}else switch(occupies){
			foreach(x; ToTuple!(["str","wstr","dstr"])){
				case mixin(`Occupies.`~x):
					assert(l.int64<mixin(x).length && r.int64<=mixin(x).length);
					return Variant(mixin(x)[cast(size_t)l.int64..cast(size_t)r.int64],Type.get!(ElementType!(typeof(mixin(x)))));
			}
			default: assert(0);
		}
	}
	Variant opSlice(size_t l, size_t r){
		return this[Variant(l,Type.get!Size_t())..Variant(r,Type.get!Size_t())];
	}
}
