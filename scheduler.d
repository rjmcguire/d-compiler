import util;
import expression; // : Node, Identifier
import semantic, scope_;

import std.algorithm, std.range, std.conv, std.string:join;
import std.typecons : Tuple, tuple;

import hashtable;

// TODO: make the Scheduler understand all parties that currently make use of
// Identifier.tryAgain. Then get rid of Identifier.tryAgain

class Scheduler{
	void add(Node root, Scope sc){
		workingset.add(root, sc);
	}

	final void remove(Node node){
		workingset.remove(node);
	}


	final void await(Node from, Node to, Scope sc)in{assert(from !is to);}body{
		workingset.await(from, to, sc);
	}
	
	struct WorkingSet{
		private enum useBuiltin = true;
		static if(useBuiltin) private template Map(K, V){ alias V[K] Map; }
		else private template Map(K,V){ alias HashMap!(K, V, "a is b","cast(size_t)cast(void*)a/16") Map; }

		Map!(Node,Scope) active;
		Map!(Node,Scope) asleep;
		
		Map!(Node,Node[]) awaited;
		
		Map!(Node,bool) done;
		
		Map!(Node,Scope) payload;

		void add(Node node, Scope sc) {
			if(node in asleep) return;
			active[node]=sc;
		}

		void remove(Node node) {
			done[node] = true;
			// dw("done with: ",node);

			active.remove(node);
			asleep.remove(node);

			foreach(v; awaited.get(node,[])){
				if(v !in asleep) continue; // TODO: why needed?
				Identifier.tryAgain = true;
				auto sc=asleep[v];
				active[v]=sc;
				asleep.remove(v);
			}
			awaited.remove(node);
		}
		
		void await(Node from, Node to, Scope sc){
			awaited[to]~=from;
			if(from !in active) return;
			if(from in asleep) return;

			asleep[from]=active[from]; // ...
			active.remove(from);
			add(to,sc);
		}

		void awake()in{assert(!active.length);}body{
			// tarjan's algorithm
			static struct Info{
				uint index;
				uint lowlink;
				uint component = -1;
				bool instack = false;
			}
			
			Info[Node] info;

			uint index = 0;
			uint component = 0;
			Node[] stack;
			void push(Node n){
				stack~=n;
				info[n].instack=true;
			}
			Node pop(){
				auto n=stack[$-1];
				stack=stack[0..$-1];
				stack.assumeSafeAppend();
				info[n].instack=false;
				return n;
			}
			void tarjan(Node n){
				info[n]=Info(index, index);
				index++;
				push(n);
				
				foreach(x;awaited.get(n,[])){
					if(x !in info){
						tarjan(x);
						info[n].lowlink = min(info[n].lowlink, info[x].lowlink);
					}else if(info[x].instack){
						info[n].lowlink = min(info[n].lowlink, info[x].index);
					}
				}
				if(info[n].index==info[n].lowlink){
					Node x;
					do{
						x = pop();
						info[x].component = component;
					}while(x !is n);
					component++;
				}
			}

			foreach(n,_; asleep) if(n !in info) tarjan(n);
			auto nodes = asleep.keys;
/+			foreach(i;0..component){
				write("component ",i,": [");
				foreach(x;nodes)
					if(info[x].component==i) write(x,",");
				writeln("]");
			}+/

			bool[] bad = new bool[component];
			
			foreach(dependee,_; asleep){
				foreach(dependent; awaited.get(dependee,[])){
					if(info[dependee].component == info[dependent].component) continue;
					bad[info[dependent].component] = true;
				}
			}
			Node[] toRemove;
			foreach(nd,sc; asleep){
				if(bad[info[nd].component]) continue;
				active[nd]=sc;
				toRemove~=nd;
			}
			foreach(nd; toRemove) asleep.remove(nd);
			
			update();
			foreach(nd,sc; payload) if(auto n=nd.isExpression()) n.noHope(sc);
			update();
		}
		
		void update(){
			// dw("active: ",active.keys);
			// dw("asleep: ",asleep.keys);
			foreach(nd,sc; active){
				if(nd.sstate == SemState.completed && !nd.needRetry
				|| nd.sstate == SemState.error || nd.rewrite)
					done[nd] = true;
			}
			foreach(nd,b; done) active.remove(nd);

			payload = active.dup();

			assert({foreach(nd,sc;payload) assert(!nd.rewrite,text(nd)); return 1;}());

			done.clear(); assert(!done.length);
		}

		void buildInterface(){
			assert(0); // TODO!
		}
		void semantic(){
			//dw(payload);
			foreach(nd,sc; payload){
				// TODO: kludgy
				auto tmpl = sc?sc.getTemplateInstance():null;
				if(tmpl){
					if(tmpl.sstate == SemState.begin) tmpl.sstate = SemState.started;
					else tmpl = null;
				}
				scope(exit) if(tmpl) tmpl.sstate = SemState.begin;
				// dw("analyzing ",nd," ",nd.sstate," ",nd.needRetry," ",!!nd.rewrite);
				if(nd.sstate == SemState.completed){
					if(nd.needRetry){
						assert(nd.needRetry && cast(Expression)nd,text(nd.needRetry," ",nd));
						(cast(Expression)cast(void*)nd).interpret(sc);
					}else remove(nd);
					continue;
				}else if(nd.sstate == SemState.error) remove(nd);
				nd.semantic(sc);
				assert(nd.needRetry != 2,nd.toString());
				//dw("done with ",nd," ",nd.sstate," ",nd.needRetry," ",!!nd.rewrite);
			}
			update();
		}
	}
	WorkingSet workingset;
	
	void run(){
		mixin(Configure!q{Identifier.tryAgain = true});
		mixin(Configure!q{Identifier.allowDelay = true});

		workingset.update();

		do{
			// dw("starting resolution pass");
			Identifier.tryAgain = true;
			do{
				Identifier.tryAgain = false;
				workingset.semantic();
			}while(Identifier.tryAgain);

			// dw("starting kill pass");
			
			Identifier.allowDelay=false;
			workingset.semantic();
			Identifier.allowDelay=true;
			//dw("workingset: ",map!(_=>text(_," ",_.sstate," ",typeid(_)))(workingset.payload.keys));
			// dw(workingset.payload.length);
			// dw(workingset.asleep.keys,"\n\n\n",workingset.awaited);
			if(!workingset.payload.length&&workingset.asleep.length)
				workingset.awake();
		}while(workingset.payload.length);

		// dw(champ," ",champ.cccc);
	}

	static Scheduler opCall(){
		static Scheduler instance;
		return instance?instance:(instance=new Scheduler);
	}
}