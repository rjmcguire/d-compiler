// Written in the D programming language.

mixin template Visitors(){
	// workaround for DMD bug: Interpret goes first
	/*static if(is(typeof({mixin Semantic!(typeof(this));})))*/
	static if(is(typeof(this):Expression)&&!is(typeof(this):Type)) mixin Interpret!(typeof(this));// TODO: minimize and report bug
	static assert(is(TypeTuple==class));
	static if(!is(typeof(this)==Symbol)&&!is(typeof(this)==TemplateInstanceDecl)&&!is(typeof(this)==ExprTuple)&&!is(typeof(this)==TypeTuple)) mixin Semantic!(typeof(this));
	// another workaround for DMD bug, other part is in expression.Node
	static if(!is(typeof(this)==Node)){
		static if(!is(typeof(this)==AggregateTy)) mixin Analyze; // wtf?
		mixin CTFEInterpret!(typeof(this));
		static if(!is(typeof(this)==AggregateTy)) mixin DeepDup!(typeof(this));
	}

	//static if(is(typeof(this)==Node))
}

import expression,declaration,type;
mixin template DeepDup(T) if(is(T: BasicType)){
	@trusted inout(T) ddup()inout{ return this; }
}

mixin template DeepDup(T) if(is(T: Node) && !is(T: BasicType)){
	@trusted inout(T) ddup()inout{
		static if(is(T:Type)){
			if(sstate==SemState.completed) return this;
			assert(sstate == SemState.begin);
		}
		enum siz = __traits(classInstanceSize,T);
		auto data = New!(void[])(siz);
		import std.c.string;
		memcpy(data.ptr, cast(void*)this, siz);
		auto res=cast(T)data.ptr;
		foreach(x;__traits(allMembers, T)){
			static if(x.length && (!is(T:Symbol)||x!="meaning" && x!="circ" && x!="clist") && x!="ctfeCallWrapper" && (!is(T==TemplateInstanceExp)||x!="eponymous"&&x!="decl")&&(!is(T==VarDecl)||x!="tupleContext") /+&& (!is(T:VarDecl)||x!="rtype")+/){ // hack
				static if(is(typeof(*mixin("&res."~x)) S) &&
					     !is(S:immutable(S))){
					static if(is(S:const(Node))){
						mixin("if(res."~x~" !is null) res."~x~"=res."~x~".ddup();");
					}else static if(is(typeof(*mixin("&res."~x)):const(Node)[])){
						mixin("res."~x~"=res."~x~".dup;");
						foreach(ref e;mixin("res."~x)) if(e!is null) e=e.ddup();
					}
				}
			}// else{ import std.stdio; writeln("not copying "~T.stringof,".",x);}
		}
		return *cast(inout(T)*)&res;
	}
}

mixin template DeepDup(T: StaticIfDecl) if(is(T==StaticIfDecl)){
	@trusted inout(T) ddup()inout{
		assert(sstate==SemState.begin||sstate==SemState.pre);
		enum siz = __traits(classInstanceSize,T);
		auto data = New!(void[])(siz);
		import std.c.string;
		memcpy(data.ptr, cast(void*)this, siz);
		auto res = cast(T)data.ptr;
		res.lazyDup = true;
		res.cond = res.cond.ddup();
		return cast(inout)res;
	}
}

import semantic;
mixin template DeepDup(T: Symbol) {
	@trusted inout(T) ddup()inout{
		enum siz = __traits(classInstanceSize,T);
		auto data = New!(void[])(siz);
		import std.c.string;
		memcpy(data.ptr, cast(void*)this, siz);
		auto res = cast(T)data.ptr;
		if(isStrong) res.meaning = res.meaning.ddup;
		return cast(inout)res;
	}
}
