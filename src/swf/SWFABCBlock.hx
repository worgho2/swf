package swf;

import format.abc.Data.ABCData;
import format.abc.Data.OpCode;

/**
	One DoABC tag of a SWF: its ABC (with its own constant pools, so its
	indices mean nothing in another block) and the opcodes of each of its
	method bodies, by function index.
**/
typedef SWFABCBlock =
{
	var abcData:ABCData;
	var pcode:Array<Array<{pos:Int, opr:OpCode}>>;
}
