package swf.exporters;

import format.abc.Data;
import swf.SWFRoot;
import lime.utils.Log;

using swf.exporters.FrameScriptParser.AVM2;
using StringTools;

class FrameScriptParser
{
	private static var indentationLevel:Int = 0;

	public static function getBaseClassName(swfData:SWFRoot, className:String):String
	{
		var block = swfData.abcBlockOf(className);
		if (block == null) return null;
		var classData = block.abcData.findClassByName(className);
		if (classData != null && classData.superclass != null)
		{
			var superClassName = block.abcData.resolveMultiNameByIndex(classData.superclass);
			switch (superClassName.nameSpace)
			{
				case NPublic(_) if (!~/^flash\./.match(superClassName.nameSpaceName)):
					if (superClassName.nameSpaceName != "")
					{
						return superClassName.nameSpaceName + "." + superClassName.name;
					}
					else
					{
						return superClassName.name;
					}
				default:
			}
		}
		return null;
	}

	/**
		The JS of the frame scripts (the frameN methods) of a class, by frame
		(index 0 is frame 1), null where the frame has none or could not be
		translated; a frame left untranslated is logged as a warning.
	**/
	public static function convertToJS(swfData:SWFRoot, className:String):Array<String>
	{
		var translation = translate(swfData, className);
		for (u in translation.untranslated)
		{
			Log.warn("Frame script " + u.frame + " of " + className + " not translated: " + u.reason);
		}
		return translation.scripts;
	}

	/**
		The frame scripts of a class translated to JS (as convertToJS) and the
		frames left untranslated, with why: an opcode the translator does not
		know (it used to drop it and translate the rest as if it were not
		there), or a script it found parsed improperly.
	**/
	public static function translate(swfData:SWFRoot, className:String):FrameScriptTranslation
	{
		var untranslated:Array<UntranslatedFrameScript> = [];
		indentationLevel = 0;
		// the block of the class: each DoABC has its own constant pools
		var block = swfData.abcBlockOf(className);
		if (block == null) return {scripts: null, untranslated: untranslated};
		var abcData = block.abcData;
		var cls = abcData.findClassByName(className);
		var scripts = null;

		if (cls != null && cls.fields != null && cls.fields.length > 0)
		{
			for (field in cls.fields)
			{
				switch (field.kind)
				{
					case FMethod(var idx, _, _, _):
						var methodName = abcData.resolveMultiNameByIndex(field.name);
						if (methodName != null && AVM2.FRAME_SCRIPT_METHOD_NAME.match(methodName.name))
						{
							var frameNumOneIndexed = Std.parseInt(AVM2.FRAME_SCRIPT_METHOD_NAME.matched(1));
							// Log.info("", "frame script #" + frameNumOneIndexed);
							var pcodes:Array<{pos:Int, opr:OpCode}> = block.pcode[idx.getIndex()];
							var js = "";
							var prop:MultiName = null;
							var stack:Array<Dynamic> = new Array();
							var closingBrackets = [];
							var openingBrackets = [];
							indentationLevel = 0;
							var cond_break:Array<String> = [];
							var in_if:Bool = false;
							var while_loops = [];
							var unsupported:Array<String> = [];

							if (pcodes != null)
							{
								for (pindex in 0...pcodes.length)
								{
									var pcode = pcodes[pindex];
									switch (pcode.opr)
									{
										case OThis:
											stack.push("this");
										case OScope:
											stack.pop();
										case OPop:
											var value = stack.pop();
											// callproperty then pop: a call whose value is dropped, a
											// statement (mxmlc without its optimizer writes stop() so)
											if (pindex > 0 && pcodes[pindex - 1].opr.match(OCallProperty(_, _)) && value != null && value != "")
											{
												js += ind() + value + ";";
											}
										case OFindPropStrict(nameIndex):
										//										prop = abcData.resolveMultiNameByIndex(nameIndex);
										case OGetLex(nameIndex):
											// Log.info("", "OGetLex: " + nameIndex);
											prop = abcData.resolveMultiNameByIndex(nameIndex);

											var fullname = "";

											if (prop != null)
											{
												fullname += AVM2.getFullName(abcData, prop, cls);
												stack.push(fullname);
											}
										case OGetProp(nameIndex):
											var fullname = "";

											prop = abcData.resolveMultiNameByIndex(nameIndex);

											if (prop != null)
											{
												if (prop.name != null)
												{
													fullname += stack.pop() + "." + AVM2.getFullName(abcData, prop, cls);
												}
												else
												{
													var name = stack.pop();
													fullname += stack.pop() + "[" + name + "]";
												}
											}

											// Log.info("", "OGetProp fullname: " + fullname);

											stack.push(fullname);
										case OSetProp(nameIndex):
											prop = abcData.resolveMultiNameByIndex(nameIndex);
											// Log.info("", "OSetProp stack: " + prop + ", " + stack);

											var result = stack.pop();

											var name = null;

											if (prop != null)
											{
												if (prop.name != null)
												{
													name = "." + prop.name;
												}
												else
												{
													name = "[" + stack.pop() + "]";
												}
											}
											else
											{
												// Log.info("", "OSetProp stack prop is null");
												break;
											}

											var instance = Std.string(stack.pop());

											if (!instance.startsWith("this"))
											{
												instance = "this" + "." + instance;
											}

											js += ind() + instance + name + " = " + result + ";";
										case OString(strIndex):
											var str = abcData.getStringByIndex(strIndex);
											stack.push("\"" + str + "\"");
										case OInt(i):
											stack.push(i);
										// Log.info("", "int: " + i);
										case OIntRef(nameIndex):
											stack.push(abcData.getIntByIndex(nameIndex));
										case OSmallInt(i):
											stack.push(i);
										// Log.info("", "smallint: " + i);
										case OFloat(nameIndex):
											stack.push(abcData.getFloatByIndex(nameIndex));
										case OCallPropVoid(nameIndex, argCount):
											var temp = AVM2.parseFunctionCall(abcData, cls, nameIndex, argCount, stack);

											var callpropvoid:String = "";

											if (stack.length > 0)
											{
												callpropvoid += stack.pop() + ".";
											}
											else
											{
												if (!temp.startsWith("this.")) callpropvoid += "this" + ".";
											}

											callpropvoid += temp;
											callpropvoid += ";";

											js += ind() + callpropvoid;
										// prop = null;
										case OCallProperty(nameIndex, argCount):
											// Log.info("", "OCallProperty stack: " + stack);

											//										stack.pop();
											//										if (prop != null)
											//										{
											//											var temp = AVM2.getFullName(abcData, prop, cls) + "." + AVM2.parseFunctionCall(abcData, cls, nameIndex, argCount, stack);
											//											trace("OCallProperty pushed to stack", temp);
											//											stack.push(temp);
											//										}

											var temp = AVM2.parseFunctionCall(abcData, cls, nameIndex, argCount, stack);

											var prop2 = abcData.resolveMultiNameByIndex(nameIndex);

											var result = "";

											if (prop2 != null)
											{
												if (prop2.name != "int")
												{
													// no receiver on the stack: the name was found on the
													// scope chain (findpropstrict), so on this, as callpropvoid
													result += (stack.length > 0 ? Std.string(stack.pop()) : "this") + "." + temp;
												}
												else
												{
													result += temp;
												}
											}

											// Log.info("", "OCallProperty result" + Std.string(result));
											stack.push(result);
										case OConstructProperty(nameIndex, argCount):
											// Log.info("", "OConstructProperty stack: " + stack);

											var temp = "";
											temp += AVM2.parseFunctionCall(abcData, cls, nameIndex, argCount, stack);
											if (temp == "int()")
											{
												temp = "0";
											}
											else if (temp.indexOf("[") == 0)
											{
												// Array
											}
											else
											{
												temp = "new " + temp;
											}
											stack.push(temp);

										// Log.info("", "OConstructProperty value: " + temp);
										case OInitProp(nameIndex):
											// Log.info("", "OInitProp stack: " + stack);

											prop = abcData.resolveMultiNameByIndex(nameIndex);

											var temp = stack.pop();

											js += ind() + stack.pop() + "." + prop.name + " = " + Std.string(temp) + ";";
										case ODup:
											stack.push(stack[stack.length - 1]);
										case OArray(argCount):
											// Log.info("", "before array: " + stack);

											var str = "";
											var temp = [];
											for (i in 0...argCount)
											{
												temp.push(stack.pop());
											}
											temp.reverse();
											stack.push(temp);

										// Log.info("", "after array: " + stack);
										case OObject(fieldCount):
											// newobject: fieldCount name/value pairs, the first pushed
											// first (sendCommand("focus", {"x": 0, ...}) of DDTank's assets)
											var fields = [];
											for (i in 0...fieldCount)
											{
												var value = stack.pop();
												var name = stack.pop();
												fields.unshift(Std.string(name) + ": " + AVM2.literal(value));
											}
											stack.push("{" + fields.join(", ") + "}");
										case ORetVoid:
										case ONull:
											stack.push(null);
										case OOp(op):
											var _operator = null;
											var incr_operator = null;

											var next_pcode = pcodes[pindex + 1];
											var _inverted:Bool = false;

											// if next pcode is OpNot
											// then we actually need to negate the boolean outcome
											if (next_pcode != null)
											{
												switch (next_pcode.opr)
												{
													case OOp(_op):
														if (_op == OpNot) _inverted = true;
													default:
												}
											}

											switch (op)
											{
												case OpMul:
													_operator = "*";
												case OpAdd:
													_operator = "+";
												case OpSub:
													_operator = "-";
												case OpDiv:
													_operator = "/";
												case OpGt:
													_operator = ">";
													if (_inverted) _operator = "<=";
												case OpLt:
													_operator = "<";
													if (_inverted) _operator = ">=";
												case OpEq:
													_operator = "==";
													if (_inverted) _operator = "!=";
												case OpPhysEq:
													_operator = "===";
													if (_inverted) _operator = "!==";
												case OpGte:
													_operator = ">=";
													if (_inverted) _operator = "<";
												case OpLte:
													_operator = "<=";
													if (_inverted) _operator = ">";
												case OpAnd:
													_operator = "&&";
												case OpOr:
													_operator = "||";
												case OpIncr:
													incr_operator = " + 1";
												case OpDecr:
													incr_operator = " - 1";
												case OpIIncr:
													incr_operator = "++";
												case OpIDecr:
													incr_operator = "--";
												case OpNot:

												case OpAs:

												default:
													// Log.warn("", "Unhandled OOp: " + op, true);
											}

											if (op == OpAs)
											{
												var discard = stack.pop();
												// Log.info("", "cast to " + discard + " is discarded");
											}

											if (_operator != null)
											{
												var temp = stack.pop();
												stack.push(Std.string(stack.pop()) + " " + _operator + " " + Std.string(temp));
											}

											if (incr_operator != null)
											{
												stack.push(Std.string(stack.pop()) + incr_operator);
											}
										case OJump(j, delta):
											var if_cond = null;

											switch (j)
											{
												case JNeq | JEq | JPhysNeq | JPhysEq | JNotGt | JNotLt | JNotGte | JNotLte | JLt | JGt | JLte | JGte:
													var _operator = null;
													var next_pcode = pcodes[pindex + 1];
													var _inverted:Bool = false;

													// if next pcode is an Always Jump,
													// then we're actually checking the opposite
													if (next_pcode != null)
													{
														switch (next_pcode.opr)
														{
															case OJump(_j, _d):
																if (_j == JAlways) _inverted = true;
															default:
														}
													}

													if (!_inverted)
													{
														switch (j)
														{
															case JNeq:
																_operator = "==";
															case JEq:
																_operator = "!=";
															case JPhysNeq:
																_operator = "===";
															case JPhysEq:
																_operator = "!==";
															case JNotGt:
																_operator = ">";
															case JNotLt:
																_operator = "<";
															case JNotGte:
																_operator = ">=";
															case JNotLte:
																_operator = "<=";
															case JLt:
																_operator = "<";
															case JGt:
																_operator = ">";
															case JLte:
																_operator = "<=";
															case JGte:
																_operator = ">=";
															default:
														}
													}
													else
													{
														switch (j)
														{
															case JNeq:
																_operator = "!=";
															case JEq:
																_operator = "==";
															case JPhysNeq:
																_operator = "!==";
															case JPhysEq:
																_operator = "===";
															case JNotGt:
																_operator = "<=";
															case JNotLt:
																_operator = ">=";
															case JNotGte:
																_operator = "<";
															case JNotLte:
																_operator = ">";
															case JLt:
																_operator = ">=";
															case JGt:
																_operator = "<=";
															case JLte:
																_operator = ">";
															case JGte:
																_operator = "<";
															default:
														}
													}

													var temp = stack.pop();

													if_cond = Std.string(stack.pop()) + " " + _operator + " " + Std.string(temp);

													if (closingBrackets.indexOf(pcode.pos + delta) == -1)
													{
														closingBrackets.push(pcode.pos + delta);
													}

												// Log.info("",
												// "indentationLevel "
												// + indentationLevel
												// + " jump style "
												// + j
												// + "closingBrackets"
												// + Std.string(closingBrackets));
												case JAlways:
													// Log.info("", "JAlways " + delta + " " + pcode.pos);

													//												if (closingBrackets.indexOf(pcode.pos + delta) == -1)
													//												{
													closingBrackets.push(pcode.pos + delta);
												//												}
												case JFalse:
													if ((pcodes[pindex - 1] != null && pcodes[pindex - 1].opr == ODup)
														&& (pcodes[pindex + 1] != null && pcodes[pindex + 1].opr == OPop))
													{
														// We are in between an "AND" if conditional
														cond_break.push("&&");
														if_cond = Std.string(stack.pop());
													}
													else
													{
														if_cond = Std.string(stack.pop());
														if (closingBrackets.indexOf(pcode.pos + delta) == -1)
														{
															closingBrackets.push(pcode.pos + delta);
														}
													}
												// Log.info("", "indentationLevel " + indentationLevel + " jump style " + j + " closingBrackets " + closingBrackets);
												case JTrue:
													if ((pcodes[pindex - 1] != null && pcodes[pindex - 1].opr == ODup)
														&& (pcodes[pindex + 1] != null && pcodes[pindex + 1].opr == OPop))
													{
														// We are in between an "OR" if conditional
														cond_break.push("||");
														if_cond = Std.string(stack.pop());
													}
													else
													{
														if_cond = "!" + Std.string(stack.pop());
														if (closingBrackets.indexOf(pcode.pos + delta) == -1)
														{
															closingBrackets.push(pcode.pos + delta);
														}
													}
												// Log.info("", "indentationLevel " + indentationLevel + " jump style " + j + " closingBrackets " + closingBrackets);
												default:
													// Log.info("", "OJump" + j + delta);
											}

											// Log.info("", Std.string(closingBrackets));

											var in_while = false;
											var out = "";
											if (if_cond != null)
											{
												if (!in_if)
												{
													if (while_loops.indexOf(pcode.pos + delta + 1) > -1)
													{
														out += "while (" + if_cond;
														in_while = true;
													}
													else
													{
														// Already have indentation from "else"
														if (js.endsWith("else "))
														{
															out += "if (" + if_cond;
														}
														else
														{
															out += ind() + "if (" + if_cond;
														}
													}
												}
												else
												{
													out += if_cond;
												}

												// If the next pcode is a OPop we're in a conditional
												if ((pcodes[pindex + 1] != null && pcodes[pindex + 1].opr == OPop)
													|| (pcodes[pindex + 2] != null && pcodes[pindex + 2].opr == OPop))
												{
													out += " " + cond_break.pop() + " ";
													in_if = true;
												}
												else
												{
													if (in_while)
													{
														out += ")";
													}
													else
													{
														out += ")" + ind() + "{";
														indentationLevel++;
													}
													in_if = false;
												}
											}

											if (while_loops.indexOf(pcode.pos + delta + 1) > -1)
											{
												js = js.replace("[[[loop" + (pcode.pos + delta + 1) + "]]]", out);
												// indentationLevel--;
												closingBrackets.push(pcode.pos);
												// js += ind() + "}";
											}
											else if (out != "")
											{
												js += out;
											}

										// Log.info("", j + " " + delta);
										case OTrue:
											stack.push(true);
										case OFalse:
											stack.push(false);
										case OLabel:
											// Indicator for while loop position
											// OJump(JAlways) can bring us back here at end of loop
											// Log.info("", "Label reached " + pcode);

											var prev_pcode = pcodes[pindex - 1];

											// if next pcode is a Label,
											// then we're actually in a while loop
											if (prev_pcode != null)
											{
												switch (prev_pcode.opr)
												{
													case OJump(_j, _delta):
														if (_j == JAlways) while_loops.push((pcode.pos));
														js += ind() + "[[[loop" + (pcode.pos) + "]]]";
														js += ind() + "{";
														indentationLevel++;
													default:
												}
											}

										case ONop | ODebugLine(_) | ODebugFile(_) | ODebugReg(_, _, _) | OBreakPoint | OBreakPointLine(_) | OTimestamp:
										// no effect on what the script does

										default:
											var name = Std.string(pcode.opr);
											if (unsupported.indexOf(name) == -1) unsupported.push(name);
									}

									for (i in 0...closingBrackets.length)
									{
										if (in_if) break;
										if (indentationLevel > -1 && pcode.pos == closingBrackets[i])
										{
											// Log.info("", "found a pcode for opening bracket" + pcode);
											if (indentationLevel > 0)
											{
												indentationLevel--;
												js += ind() + "}";
											}
											closingBrackets.remove(i);
											// Log.info("", "decreased indentationLevel" + indentationLevel + " " + closingBrackets);

											switch (pcode.opr)
											{
												case OJump(j, delta):
													if (j == JAlways)
													{
														if (delta < 0) break; // return null;
														js += ind() + "else ";

														var foundConditionals = false;

														for (k in pcodes.indexOf(pcode) + 1...pcodes.length)
														{
															// Log.info("", "pcodes to look for conditional" + pcodes[k]);

															switch (pcodes[k].opr)
															{
																case OSetProp(_) | OCallPropVoid(_, _) | OInitProp(_):
																	foundConditionals = false;
																	break;
																case OJump(_, _):
																	foundConditionals = true;
																	break;
																default:
															}

															if (pcodes[k].pos > pcode.pos + delta)
															{
																break;
															}
															else
															{
																// if (pcodes[k].opr.match(OJump(j2, delta2)))
																// {
																// 	foundConditionals = true;
																// }
																switch (pcodes[k].opr)
																{
																	case OJump(j2, delta2):
																		if (j == j2 && delta == delta2)
																		{
																			foundConditionals = true;
																		}
																	default:
																}
															}
														}

														// Log.info("", "foundConditionals" + foundConditionals);
														if (!foundConditionals)
														{
															js += ind() + "{";
															indentationLevel += 1;
															// Log.info("", "indentationLevel" + j + indentationLevel + closingBrackets);
														}
													}
												default:
											}
											//										break;
										}

										//									if (pcode.pos == openingBrackets[i])
										//									{
										//										trace("found a pcode for a OJump (JNeq)", pcode);
										//										openingBrackets.remove(i);
										//
										//										var index = pcodes.indexOf(pcode);
										//
										//										if (index + 1 < pcodes.length - 1)
										//										{
										//											switch (pcodes[index + 1].opr)
										//											{
										//												case OJump(jumpStyle, delta):
										//													trace("pcode is OJump", jumpStyle);
										//												default:
										//													trace("pcode", pcodes[index + 1].opr);
										//											}
										//										}
										//
										//										js += ind() + "{ \\\\opening\n";
										//										break;
										//									}
									}
								}
							}

							var _force_close = (indentationLevel > 0);
							while (indentationLevel > 0)
							{
								indentationLevel--;
								js += ind() + "}";
							}
							if (_force_close) js += ind() + "// force close due to same bracket close collision, double-check statements";

							// take care of common replacements
							// AS3's int() is no JS function: parseInt, also as an argument.
							// Until nothing changes: each match consumes the character before
							// int(, so the int( right inside another (int(int(x))) is left
							// for the next pass.
							var intCall = ~/(^|[^\w.$])int\(/g;
							var previous = null;
							while (previous != js)
							{
								previous = js;
								js = intCall.replace(js, "$1parseInt(");
							}
							js = js.replace("flash_", "openfl_");
							js = js.replace("flash.", "openfl.");
							js = js.replace("fl_motion", "wwlib_graphics");
							js = js.replace("this.console", "console"); // hack to get trace statements working

							// Log.info("", "javascript:\n" + js);

							// Log.info("", Std.string(pcodes));

							if (unsupported.length > 0)
							{
								untranslated.push({frame: frameNumOneIndexed, reason: "unsupported opcodes: " + unsupported.join(", ")});
							}
							else if (js != null && js.indexOf("null.") > -1)
							{
								// Log.info("", "Script appears to have been parsed improperly, discarding");
								untranslated.push({frame: frameNumOneIndexed, reason: "parsed improperly (null. in the JS)"});
							}
							else
							{
								// store on SWFLite object for serialized .dat export
								if (scripts == null) scripts = [];
								scripts[frameNumOneIndexed - 1] = js;
							}
						}
					default:
				}
			}
		}

		return {scripts: scripts, untranslated: untranslated};
	}

	private static function ind():String
	{
		var a:String = "\n";
		for (_ in 0...indentationLevel)
			a += "	";
		return a;
	}
}

/** What FrameScriptParser.translate gives for a class. */
typedef FrameScriptTranslation =
{
	/** The JS by frame (index 0 is frame 1), null where none; null if none at all. */
	var scripts:Array<String>;
	/** The frames left without a script although the class has one for them. */
	var untranslated:Array<UntranslatedFrameScript>;
}

typedef UntranslatedFrameScript =
{
	/** The frame, 1-based (frameN). */
	var frame:Int;
	var reason:String;
}

/**
 * AVM2 ActionScript3 Byte Code (ABC) Instruction Traversal
 */
private typedef MultiName =
{
	var name:String;
	var nameIndex:Index<Name>;
	var nameSpace:Namespace;
	var nameSpaceName:String;
}

class AVM2
{
	public static var FRAME_SCRIPT_METHOD_NAME = ~/frame(\d+)/;

	public static function getIndex<T>(idx:Index<T>):Int
	{
		#if (haxe4 || (format > "3.4.2"))
		return idx.asInt();
		#else
		return switch (idx)
		{
			case Idx(i): i;
		};
		#end
	}

	public static function getIntByIndex(abcData:ABCData, i:Index<Int>):Int
	{
		return abcData.ints[i.getIndex() - 1];
	}

	public static function getFloatByIndex(abcData:ABCData, i:Index<Float>):Float
	{
		return abcData.floats[i.getIndex() - 1];
	}

	public static function getMultiNameByIndex(abcData:ABCData, i:Index<Name>):Name
	{
		return abcData.names[i.getIndex() - 1];
	}

	public static function getStringByIndex(abcData:ABCData, i:Index<String>):String
	{
		return abcData.strings[i.getIndex() - 1];
	}

	public static function getNameSpaceByIndex(abcData:ABCData, i:Index<Namespace>):Namespace
	{
		return abcData.namespaces[i.getIndex() - 1];
	}

	public static function getFunctionByIndex(abcData:ABCData, i:Index<MethodType>):Function
	{
		return abcData.functions[i.getIndex()];
	}

	public static function resolveMultiNameByIndex(abcData:ABCData, i:Index<Name>):MultiName
	{
		var multiName = abcData.getMultiNameByIndex(i);
		switch (multiName)
		{
			case NName(nameIndex, nsIndex): // a.k.a. QName
				var nameSpace = abcData.getNameSpaceByIndex(nsIndex);
				switch (nameSpace)
				{
					case NPublic(nsNameIndex) | NInternal(nsNameIndex) | NPrivate(nsNameIndex) | NProtected(nsNameIndex): // a.k.a. PackageNamespace, PackageInternalNS
						return {
							name: abcData.getStringByIndex(nameIndex),
							nameIndex: i,
							nameSpace: nameSpace,
							nameSpaceName: abcData.getStringByIndex(nsNameIndex)
						}
					default:
						// Log.info("", "other type of namespace");
				}
			case NMulti(nameIndex, nsIndexSet):
				return {
					name: abcData.getStringByIndex(nameIndex),
					nameIndex: i,
					nameSpace: null,
					nameSpaceName: null
				}
			case NMultiLate(nset):
				return {
					name: null,
					nameIndex: i,
					nameSpace: null,
					nameSpaceName: null
				}
			default:
				// Log.info("", "other type of name");
		}
		return null;
	}

	public static function findClassByName(abcData:ABCData, s:String):ClassDef
	{
		if (s == null) return null;

		var x = s.lastIndexOf(".");
		var pkgName = "";
		var clsName = s;
		if (-1 != x)
		{
			pkgName = s.substr(0, x);
			clsName = s.substr(x + 1);
		}
		for (cls in abcData.classes)
		{
			if (cls.isInterface) continue;

			var multiName = abcData.resolveMultiNameByIndex(cls.name);

			if (multiName != null)
			{
				if (clsName == multiName.name && pkgName == multiName.nameSpaceName)
				{
					return cls;
				}
			}
			else
			{
				// Log.info("", "multiname: " + multiName);
			}
		}

		return null;
	}

	public static function classHasField(abcData:ABCData, cls:ClassDef, name:String):Bool
	{
		var classHasField = false;

		for (field in cls.fields)
		{
			switch (field.kind)
			{
				case FMethod(var idx, _, _, _):
					var methodName = abcData.resolveMultiNameByIndex(field.name);
					if (methodName.name == name)
					{
						classHasField = true;
						break;
					}
				case FVar(_, _, _):
					var methodName = abcData.resolveMultiNameByIndex(field.name);
					if (methodName.name == name)
					{
						classHasField = true;
						break;
					}
				default:
			}
		}

		return classHasField;
	}

	public static function getFullName(abcData:ABCData, prop:MultiName, cls:ClassDef):String
	{
		var js = null;

		if (prop == null)
		{
			// Log.info("", "unable to get full name of property, prop = null");
			return "";
		}

		if (prop.nameSpace == null)
		{
			// Log.info("", "namespace is null");
			js = prop.name;
		}
		else
		{
			switch (prop.nameSpace)
			{
				case NPublic(_) if ("" != prop.nameSpaceName):
					js = prop.nameSpaceName.replace(".", "_") + "_" + prop.name;
				case NInternal(_) if (cls.name == prop.nameIndex):
					js = "this." + prop.name;
				case NPublic(_):
					switch (prop.name)
					{
						case "trace":
							js = "console.log";
						default:
							//						var classHasField = classHasField(abcData, cls, prop.name);
							//
							//						if (classHasField)
							//						{
							//							js = "this." + prop.name;
							//						}
							//						else
							//						{
							js = prop.name;
							//						}
					}
				// A protected namespace is named after its class
				// ("road.game.resource:ActionMovie"), never a package: the name is
				// a member of the instance, like the private and internal ones (a
				// frame script calling sendCommand of the SWF's ActionMovie).
				case NPrivate(_) | NInternal(_) | NProtected(_):
					// Log.info("", "Namespace " + prop.nameSpace + " " + prop.name);
					js = prop.name;
				default:
					// TODO: throw() on unsupported namespaces
					// Log.info("", "unsupported namespace " + prop.nameSpace);
			}
		}

		return js;
	}

	/** A value of the translator's stack as JS: a String is already code (a
		quoted string, an expression), anything else (Int, Float, Bool, null)
		is written as JSON. */
	public static function literal(value:Dynamic):String
	{
		return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (value, String) ? value : haxe.Json.stringify(value);
	}

	public static function parseFunctionCall(abcData:ABCData, cls:ClassDef, nameIndex:IName, argCount:Int, stack:Array<Dynamic>):String
	{
		var is_array:Bool = false;
		var prop = abcData.resolveMultiNameByIndex(nameIndex);

		if (prop == null)
		{
			// Log.info("", "parseFunctionCall is stopped, prop = null");
			return "";
		}

		var js = getFullName(abcData, prop, cls);
		if (js == "Array")
		{
			js = "[";
			is_array = true;
		}
		else
		{
			// invoke function
			js += "(";
		}

		var temp = [];
		for (i in 0...argCount)
		{
			temp.push(literal(stack.pop()));
		}
		temp.reverse();
		js += temp.join(", ");
		if (is_array)
		{
			js += "]";
		}
		else
		{
			js += ")";
		}

		return js;
	}
}
