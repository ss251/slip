var __slipContract = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // build/contract/index.js
  var index_exports = {};
  __export(index_exports, {
    Contract: () => Contract,
    SlipStatus: () => SlipStatus,
    contractReferenceLocations: () => contractReferenceLocations,
    ledger: () => ledger,
    pureCircuits: () => pureCircuits
  });

  // build/runtime-global.js
  var r = globalThis.__compactRuntime;
  var { ChargedState, CompactError, CompactTypeBoolean, CompactTypeBytes, CompactTypeEnum, CompactTypeUnsignedInteger, CompactTypeVector, ContractOperation, ContractState, CostModel, QueryContext, StateMap, StateValue, assert, checkRuntimeVersion, convertFieldToBytes, createCircuitContext, createWitnessContext, dummyContractAddress, emptyRunningCost, persistentCommit, persistentHash, queryLedgerState, typeError, valueToBigInt } = r;

  // build/contract/index.js
  checkRuntimeVersion("0.16.0");
  var SlipStatus;
  (function(SlipStatus2) {
    SlipStatus2[SlipStatus2["draft"] = 0] = "draft";
    SlipStatus2[SlipStatus2["open"] = 1] = "open";
    SlipStatus2[SlipStatus2["settled"] = 2] = "settled";
    SlipStatus2[SlipStatus2["disputed"] = 3] = "disputed";
  })(SlipStatus || (SlipStatus = {}));
  var _descriptor_0 = new CompactTypeUnsignedInteger(18446744073709551615n, 8);
  var _descriptor_1 = new CompactTypeEnum(3, 1);
  var _descriptor_2 = new CompactTypeUnsignedInteger(255n, 1);
  var _descriptor_3 = new CompactTypeBytes(32);
  var _descriptor_4 = CompactTypeBoolean;
  var _descriptor_5 = new CompactTypeUnsignedInteger(65535n, 2);
  var _descriptor_6 = new CompactTypeVector(2, _descriptor_3);
  var _descriptor_7 = new CompactTypeVector(4, _descriptor_3);
  var _descriptor_8 = new CompactTypeVector(3, _descriptor_3);
  var _Either_0 = class {
    alignment() {
      return _descriptor_4.alignment().concat(_descriptor_3.alignment().concat(_descriptor_3.alignment()));
    }
    fromValue(value_0) {
      return {
        is_left: _descriptor_4.fromValue(value_0),
        left: _descriptor_3.fromValue(value_0),
        right: _descriptor_3.fromValue(value_0)
      };
    }
    toValue(value_0) {
      return _descriptor_4.toValue(value_0.is_left).concat(_descriptor_3.toValue(value_0.left).concat(_descriptor_3.toValue(value_0.right)));
    }
  };
  var _descriptor_9 = new _Either_0();
  var _descriptor_10 = new CompactTypeUnsignedInteger(340282366920938463463374607431768211455n, 16);
  var _ContractAddress_0 = class {
    alignment() {
      return _descriptor_3.alignment();
    }
    fromValue(value_0) {
      return {
        bytes: _descriptor_3.fromValue(value_0)
      };
    }
    toValue(value_0) {
      return _descriptor_3.toValue(value_0.bytes);
    }
  };
  var _descriptor_11 = new _ContractAddress_0();
  var Contract = class {
    witnesses;
    constructor(...args_0) {
      if (args_0.length !== 1) {
        throw new CompactError(`Contract constructor: expected 1 argument, received ${args_0.length}`);
      }
      const witnesses_0 = args_0[0];
      if (typeof witnesses_0 !== "object") {
        throw new CompactError("first (witnesses) argument to Contract constructor is not an object");
      }
      if (typeof witnesses_0.localSecretKey !== "function") {
        throw new CompactError("first (witnesses) argument to Contract constructor does not contain a function-valued field named localSecretKey");
      }
      if (typeof witnesses_0.localPick !== "function") {
        throw new CompactError("first (witnesses) argument to Contract constructor does not contain a function-valued field named localPick");
      }
      this.witnesses = witnesses_0;
      this.circuits = {
        memberIdOf(context, ...args_1) {
          return { result: pureCircuits.memberIdOf(...args_1), context };
        },
        pickSaltOf(context, ...args_1) {
          return { result: pureCircuits.pickSaltOf(...args_1), context };
        },
        pickCommitment(context, ...args_1) {
          return { result: pureCircuits.pickCommitment(...args_1), context };
        },
        createSlip: (...args_1) => {
          if (args_1.length !== 3) {
            throw new CompactError(`createSlip: expected 3 arguments (as invoked from Typescript), received ${args_1.length}`);
          }
          const contextOrig_0 = args_1[0];
          const question_0 = args_1[1];
          const deadline_0 = args_1[2];
          if (!(typeof contextOrig_0 === "object" && contextOrig_0.currentQueryContext != void 0)) {
            typeError(
              "createSlip",
              "argument 1 (as invoked from Typescript)",
              "slip.compact line 344 char 1",
              "CircuitContext",
              contextOrig_0
            );
          }
          if (!(question_0.buffer instanceof ArrayBuffer && question_0.BYTES_PER_ELEMENT === 1 && question_0.length === 32)) {
            typeError(
              "createSlip",
              "argument 1 (argument 2 as invoked from Typescript)",
              "slip.compact line 344 char 1",
              "Bytes<32>",
              question_0
            );
          }
          if (!(typeof deadline_0 === "bigint" && deadline_0 >= 0n && deadline_0 <= 18446744073709551615n)) {
            typeError(
              "createSlip",
              "argument 2 (argument 3 as invoked from Typescript)",
              "slip.compact line 344 char 1",
              "Uint<0..18446744073709551616>",
              deadline_0
            );
          }
          const context = { ...contextOrig_0, gasCost: emptyRunningCost() };
          const partialProofData = {
            input: {
              value: _descriptor_3.toValue(question_0).concat(_descriptor_0.toValue(deadline_0)),
              alignment: _descriptor_3.alignment().concat(_descriptor_0.alignment())
            },
            output: void 0,
            publicTranscript: [],
            privateTranscriptOutputs: []
          };
          const result_0 = this._createSlip_0(
            context,
            partialProofData,
            question_0,
            deadline_0
          );
          partialProofData.output = { value: [], alignment: [] };
          return { result: result_0, context, proofData: partialProofData, gasCost: context.gasCost };
        },
        enrollMember: (...args_1) => {
          if (args_1.length !== 2) {
            throw new CompactError(`enrollMember: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
          }
          const contextOrig_0 = args_1[0];
          const memberId_0 = args_1[1];
          if (!(typeof contextOrig_0 === "object" && contextOrig_0.currentQueryContext != void 0)) {
            typeError(
              "enrollMember",
              "argument 1 (as invoked from Typescript)",
              "slip.compact line 443 char 1",
              "CircuitContext",
              contextOrig_0
            );
          }
          if (!(memberId_0.buffer instanceof ArrayBuffer && memberId_0.BYTES_PER_ELEMENT === 1 && memberId_0.length === 32)) {
            typeError(
              "enrollMember",
              "argument 1 (argument 2 as invoked from Typescript)",
              "slip.compact line 443 char 1",
              "Bytes<32>",
              memberId_0
            );
          }
          const context = { ...contextOrig_0, gasCost: emptyRunningCost() };
          const partialProofData = {
            input: {
              value: _descriptor_3.toValue(memberId_0),
              alignment: _descriptor_3.alignment()
            },
            output: void 0,
            publicTranscript: [],
            privateTranscriptOutputs: []
          };
          const result_0 = this._enrollMember_0(
            context,
            partialProofData,
            memberId_0
          );
          partialProofData.output = { value: [], alignment: [] };
          return { result: result_0, context, proofData: partialProofData, gasCost: context.gasCost };
        },
        sealPick: (...args_1) => {
          if (args_1.length !== 1) {
            throw new CompactError(`sealPick: expected 1 argument (as invoked from Typescript), received ${args_1.length}`);
          }
          const contextOrig_0 = args_1[0];
          if (!(typeof contextOrig_0 === "object" && contextOrig_0.currentQueryContext != void 0)) {
            typeError(
              "sealPick",
              "argument 1 (as invoked from Typescript)",
              "slip.compact line 456 char 1",
              "CircuitContext",
              contextOrig_0
            );
          }
          const context = { ...contextOrig_0, gasCost: emptyRunningCost() };
          const partialProofData = {
            input: { value: [], alignment: [] },
            output: void 0,
            publicTranscript: [],
            privateTranscriptOutputs: []
          };
          const result_0 = this._sealPick_0(context, partialProofData);
          partialProofData.output = { value: [], alignment: [] };
          return { result: result_0, context, proofData: partialProofData, gasCost: context.gasCost };
        },
        reveal: (...args_1) => {
          if (args_1.length !== 1) {
            throw new CompactError(`reveal: expected 1 argument (as invoked from Typescript), received ${args_1.length}`);
          }
          const contextOrig_0 = args_1[0];
          if (!(typeof contextOrig_0 === "object" && contextOrig_0.currentQueryContext != void 0)) {
            typeError(
              "reveal",
              "argument 1 (as invoked from Typescript)",
              "slip.compact line 489 char 1",
              "CircuitContext",
              contextOrig_0
            );
          }
          const context = { ...contextOrig_0, gasCost: emptyRunningCost() };
          const partialProofData = {
            input: { value: [], alignment: [] },
            output: void 0,
            publicTranscript: [],
            privateTranscriptOutputs: []
          };
          const result_0 = this._reveal_0(context, partialProofData);
          partialProofData.output = { value: [], alignment: [] };
          return { result: result_0, context, proofData: partialProofData, gasCost: context.gasCost };
        },
        settle: (...args_1) => {
          if (args_1.length !== 2) {
            throw new CompactError(`settle: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
          }
          const contextOrig_0 = args_1[0];
          const result_1 = args_1[1];
          if (!(typeof contextOrig_0 === "object" && contextOrig_0.currentQueryContext != void 0)) {
            typeError(
              "settle",
              "argument 1 (as invoked from Typescript)",
              "slip.compact line 546 char 1",
              "CircuitContext",
              contextOrig_0
            );
          }
          if (!(typeof result_1 === "bigint" && result_1 >= 0n && result_1 <= 255n)) {
            typeError(
              "settle",
              "argument 1 (argument 2 as invoked from Typescript)",
              "slip.compact line 546 char 1",
              "Uint<0..256>",
              result_1
            );
          }
          const context = { ...contextOrig_0, gasCost: emptyRunningCost() };
          const partialProofData = {
            input: {
              value: _descriptor_2.toValue(result_1),
              alignment: _descriptor_2.alignment()
            },
            output: void 0,
            publicTranscript: [],
            privateTranscriptOutputs: []
          };
          const result_0 = this._settle_0(context, partialProofData, result_1);
          partialProofData.output = { value: [], alignment: [] };
          return { result: result_0, context, proofData: partialProofData, gasCost: context.gasCost };
        },
        dispute: (...args_1) => {
          if (args_1.length !== 1) {
            throw new CompactError(`dispute: expected 1 argument (as invoked from Typescript), received ${args_1.length}`);
          }
          const contextOrig_0 = args_1[0];
          if (!(typeof contextOrig_0 === "object" && contextOrig_0.currentQueryContext != void 0)) {
            typeError(
              "dispute",
              "argument 1 (as invoked from Typescript)",
              "slip.compact line 588 char 1",
              "CircuitContext",
              contextOrig_0
            );
          }
          const context = { ...contextOrig_0, gasCost: emptyRunningCost() };
          const partialProofData = {
            input: { value: [], alignment: [] },
            output: void 0,
            publicTranscript: [],
            privateTranscriptOutputs: []
          };
          const result_0 = this._dispute_0(context, partialProofData);
          partialProofData.output = { value: [], alignment: [] };
          return { result: result_0, context, proofData: partialProofData, gasCost: context.gasCost };
        }
      };
      this.impureCircuits = {
        createSlip: this.circuits.createSlip,
        enrollMember: this.circuits.enrollMember,
        sealPick: this.circuits.sealPick,
        reveal: this.circuits.reveal,
        settle: this.circuits.settle,
        dispute: this.circuits.dispute
      };
      this.provableCircuits = {
        createSlip: this.circuits.createSlip,
        enrollMember: this.circuits.enrollMember,
        sealPick: this.circuits.sealPick,
        reveal: this.circuits.reveal,
        settle: this.circuits.settle,
        dispute: this.circuits.dispute
      };
    }
    initialState(...args_0) {
      if (args_0.length !== 1) {
        throw new CompactError(`Contract state constructor: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
      }
      const constructorContext_0 = args_0[0];
      if (typeof constructorContext_0 !== "object") {
        throw new CompactError(`Contract state constructor: expected 'constructorContext' in argument 1 (as invoked from Typescript) to be an object`);
      }
      if (!("initialPrivateState" in constructorContext_0)) {
        throw new CompactError(`Contract state constructor: expected 'initialPrivateState' in argument 1 (as invoked from Typescript)`);
      }
      if (!("initialZswapLocalState" in constructorContext_0)) {
        throw new CompactError(`Contract state constructor: expected 'initialZswapLocalState' in argument 1 (as invoked from Typescript)`);
      }
      if (typeof constructorContext_0.initialZswapLocalState !== "object") {
        throw new CompactError(`Contract state constructor: expected 'initialZswapLocalState' in argument 1 (as invoked from Typescript) to be an object`);
      }
      const state_0 = new ContractState();
      let stateValue_0 = StateValue.newArray();
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      stateValue_0 = stateValue_0.arrayPush(StateValue.newNull());
      state_0.data = new ChargedState(stateValue_0);
      state_0.setOperation("createSlip", new ContractOperation());
      state_0.setOperation("enrollMember", new ContractOperation());
      state_0.setOperation("sealPick", new ContractOperation());
      state_0.setOperation("reveal", new ContractOperation());
      state_0.setOperation("settle", new ContractOperation());
      state_0.setOperation("dispute", new ContractOperation());
      const context = createCircuitContext(dummyContractAddress(), constructorContext_0.initialZswapLocalState.coinPublicKey, state_0.data, constructorContext_0.initialPrivateState);
      const partialProofData = {
        input: { value: [], alignment: [] },
        output: void 0,
        publicTranscript: [],
        privateTranscriptOutputs: []
      };
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(0n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_1.toValue(0),
              alignment: _descriptor_1.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(1n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(new Uint8Array(32)),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(2n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(new Uint8Array(32)),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(3n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(4n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(5n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(6n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(7n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(8n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newMap(
              new StateMap()
            ).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(9n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newMap(
              new StateMap()
            ).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(10n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newMap(
              new StateMap()
            ).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(11n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(12n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(13n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(0n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(14n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(new Uint8Array(32)),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_0 = this._persistentHash_1([
        new Uint8Array([115, 108, 105, 112, 58, 115, 116, 101, 119, 97, 114, 100, 58, 118, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        this._localSecretKey_0(
          context,
          partialProofData
        )
      ]);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(1n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(tmp_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(0n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_1.toValue(0),
              alignment: _descriptor_1.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_1 = new Uint8Array(32);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(2n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(tmp_1),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_2 = 0n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(3n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_2),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_3 = 0n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(4n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_3),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_4 = 0n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(5n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_4),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_5 = 0n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(6n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_5),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_6 = 2n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(13n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(tmp_6),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_7 = new Uint8Array(32);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(14n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(tmp_7),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      state_0.data = new ChargedState(context.currentQueryContext.state.state);
      return {
        currentContractState: state_0,
        currentPrivateState: context.currentPrivateState,
        currentZswapLocalState: context.currentZswapLocalState
      };
    }
    _blockTimeLt_0(context, partialProofData, time_0) {
      return _descriptor_4.fromValue(queryLedgerState(
        context,
        partialProofData,
        [
          { dup: { n: 2 } },
          { idx: {
            cached: true,
            pushPath: false,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(2n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(time_0),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          "lt",
          { popeq: {
            cached: true,
            result: void 0
          } }
        ]
      ).value);
    }
    _blockTimeGte_0(context, partialProofData, time_0) {
      return !this._blockTimeLt_0(context, partialProofData, time_0);
    }
    _persistentHash_0(value_0) {
      const result_0 = persistentHash(_descriptor_8, value_0);
      return result_0;
    }
    _persistentHash_1(value_0) {
      const result_0 = persistentHash(_descriptor_6, value_0);
      return result_0;
    }
    _persistentCommit_0(value_0, rand_0) {
      const result_0 = persistentCommit(
        _descriptor_7,
        value_0,
        rand_0
      );
      return result_0;
    }
    _localSecretKey_0(context, partialProofData) {
      const witnessContext_0 = createWitnessContext(ledger(context.currentQueryContext.state), context.currentPrivateState, context.currentQueryContext.address);
      const [nextPrivateState_0, result_0] = this.witnesses.localSecretKey(witnessContext_0);
      context.currentPrivateState = nextPrivateState_0;
      if (!(result_0.buffer instanceof ArrayBuffer && result_0.BYTES_PER_ELEMENT === 1 && result_0.length === 32)) {
        typeError(
          "localSecretKey",
          "return value",
          "slip.compact line 204 char 1",
          "Bytes<32>",
          result_0
        );
      }
      partialProofData.privateTranscriptOutputs.push({
        value: _descriptor_3.toValue(result_0),
        alignment: _descriptor_3.alignment()
      });
      return result_0;
    }
    _localPick_0(context, partialProofData) {
      const witnessContext_0 = createWitnessContext(ledger(context.currentQueryContext.state), context.currentPrivateState, context.currentQueryContext.address);
      const [nextPrivateState_0, result_0] = this.witnesses.localPick(witnessContext_0);
      context.currentPrivateState = nextPrivateState_0;
      if (!(typeof result_0 === "bigint" && result_0 >= 0n && result_0 <= 255n)) {
        typeError(
          "localPick",
          "return value",
          "slip.compact line 207 char 1",
          "Uint<0..256>",
          result_0
        );
      }
      partialProofData.privateTranscriptOutputs.push({
        value: _descriptor_2.toValue(result_0),
        alignment: _descriptor_2.alignment()
      });
      return result_0;
    }
    _memberIdOf_0(sk_0) {
      return this._persistentHash_1([
        new Uint8Array([115, 108, 105, 112, 58, 109, 101, 109, 98, 101, 114, 58, 118, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        sk_0
      ]);
    }
    _pickSaltOf_0(round_0, sk_0) {
      return this._persistentHash_0([
        new Uint8Array([115, 108, 105, 112, 58, 112, 105, 99, 107, 115, 97, 108, 116, 58, 118, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        convertFieldToBytes(
          32,
          round_0,
          "slip.compact line 246 char 42"
        ),
        sk_0
      ]);
    }
    _pickCommitment_0(round_0, memberId_0, choice_0, salt_0) {
      return this._persistentCommit_0(
        [
          new Uint8Array([115, 108, 105, 112, 58, 112, 105, 99, 107, 58, 118, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
          convertFieldToBytes(
            32,
            round_0,
            "slip.compact line 265 char 13"
          ),
          memberId_0,
          convertFieldToBytes(
            32,
            choice_0,
            "slip.compact line 267 char 13"
          )
        ],
        salt_0
      );
    }
    _assertSteward_0(context, partialProofData) {
      const claimed_0 = this._persistentHash_1([
        new Uint8Array([115, 108, 105, 112, 58, 115, 116, 101, 119, 97, 114, 100, 58, 118, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        this._localSecretKey_0(
          context,
          partialProofData
        )
      ]);
      assert(
        this._equal_0(
          claimed_0,
          _descriptor_3.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(1n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "not the steward"
      );
      return [];
    }
    _createSlip_0(context, partialProofData, question_0, deadline_0) {
      this._assertSteward_0(context, partialProofData);
      assert(
        this._blockTimeGte_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(6n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "the current slip has not closed yet"
      );
      const publicDeadline_0 = deadline_0;
      const tooSoonBound_0 = publicDeadline_0 >= 300n ? (assert(
        publicDeadline_0 >= 300n,
        "result of subtraction would be negative"
      ), publicDeadline_0 - 300n) : 0n;
      assert(
        this._blockTimeLt_0(
          context,
          partialProofData,
          tooSoonBound_0
        ),
        "deadline must be more than 5 minutes out"
      );
      const tooFarBound_0 = publicDeadline_0 >= 31536000n ? (assert(
        publicDeadline_0 >= 31536000n,
        "result of subtraction would be negative"
      ), publicDeadline_0 - 31536000n) : 0n;
      assert(
        this._blockTimeGte_0(
          context,
          partialProofData,
          tooFarBound_0
        ),
        "deadline must be within 365 days (seconds since epoch, not milliseconds)"
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(9n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newMap(
              new StateMap()
            ).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(10n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newMap(
              new StateMap()
            ).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(11n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(12n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(0n),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_0 = 1n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { idx: {
            cached: false,
            pushPath: true,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(7n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { addi: { immediate: parseInt(valueToBigInt(
            {
              value: _descriptor_5.toValue(tmp_0),
              alignment: _descriptor_5.alignment()
            }.value
          )) } },
          { ins: { cached: true, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(2n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(question_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(3n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(publicDeadline_0),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_1 = ((t1) => {
        if (t1 > 18446744073709551615n) {
          throw new CompactError("slip.compact line 413 char 20: cast from Field or Uint value to smaller Uint value failed: " + t1 + " is greater than 18446744073709551615");
        }
        return t1;
      })(publicDeadline_0 + 86400n);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(4n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_1),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_2 = ((t1) => {
        if (t1 > 18446744073709551615n) {
          throw new CompactError("slip.compact line 418 char 20: cast from Field or Uint value to smaller Uint value failed: " + t1 + " is greater than 18446744073709551615");
        }
        return t1;
      })(publicDeadline_0 + 86400n + 43200n);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(5n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_2),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_3 = ((t1) => {
        if (t1 > 18446744073709551615n) {
          throw new CompactError("slip.compact line 423 char 21: cast from Field or Uint value to smaller Uint value failed: " + t1 + " is greater than 18446744073709551615");
        }
        return t1;
      })(publicDeadline_0 + 86400n + 43200n + 43200n);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(6n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_0.toValue(tmp_3),
              alignment: _descriptor_0.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_4 = 2n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(13n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(tmp_4),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      const tmp_5 = new Uint8Array(32);
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(14n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(tmp_5),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(0n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_1.toValue(1),
              alignment: _descriptor_1.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      return [];
    }
    _enrollMember_0(context, partialProofData, memberId_0) {
      this._assertSteward_0(context, partialProofData);
      assert(
        _descriptor_1.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(0n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value) !== 1,
        "the roster is locked while a slip is open"
      );
      const publicMemberId_0 = memberId_0;
      assert(
        !_descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(8n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "already enrolled"
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { idx: {
            cached: false,
            pushPath: true,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(8n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(publicMemberId_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newNull().encode()
          } },
          { ins: { cached: false, n: 1 } },
          { ins: { cached: true, n: 1 } }
        ]
      );
      return [];
    }
    _sealPick_0(context, partialProofData) {
      assert(
        _descriptor_1.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(0n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value) === 1,
        "no slip is open"
      );
      assert(
        this._blockTimeLt_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(3n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "sealing has closed"
      );
      const memberId_0 = this._memberIdOf_0(this._localSecretKey_0(
        context,
        partialProofData
      ));
      const publicMemberId_0 = memberId_0;
      assert(
        _descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(8n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "not in this crew"
      );
      assert(
        !_descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(9n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "already sealed this round"
      );
      const choice_0 = this._localPick_0(context, partialProofData);
      assert(choice_0 < 2n, "pick must be 0 (No) or 1 (Yes)");
      const round_0 = _descriptor_0.fromValue(queryLedgerState(
        context,
        partialProofData,
        [
          { dup: { n: 0 } },
          { idx: {
            cached: false,
            pushPath: false,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(7n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { popeq: {
            cached: true,
            result: void 0
          } }
        ]
      ).value);
      const tmp_0 = this._pickCommitment_0(
        round_0,
        memberId_0,
        choice_0,
        this._pickSaltOf_0(
          round_0,
          this._localSecretKey_0(
            context,
            partialProofData
          )
        )
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { idx: {
            cached: false,
            pushPath: true,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(9n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(publicMemberId_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(tmp_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } },
          { ins: { cached: true, n: 1 } }
        ]
      );
      return [];
    }
    _reveal_0(context, partialProofData) {
      assert(
        _descriptor_1.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(0n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value) !== 0,
        "no slip to reveal"
      );
      assert(
        this._blockTimeGte_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(3n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "reveals open at the seal deadline"
      );
      assert(
        this._blockTimeLt_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(4n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "the reveal window has closed"
      );
      const memberId_0 = this._memberIdOf_0(this._localSecretKey_0(
        context,
        partialProofData
      ));
      const publicMemberId_0 = memberId_0;
      assert(
        _descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(9n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "nothing sealed for this member"
      );
      assert(
        !_descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(10n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "already revealed this round"
      );
      const choice_0 = this._localPick_0(context, partialProofData);
      assert(choice_0 < 2n, "pick must be 0 (No) or 1 (Yes)");
      const round_0 = _descriptor_0.fromValue(queryLedgerState(
        context,
        partialProofData,
        [
          { dup: { n: 0 } },
          { idx: {
            cached: false,
            pushPath: false,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(7n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { popeq: {
            cached: true,
            result: void 0
          } }
        ]
      ).value);
      const recomputed_0 = this._pickCommitment_0(
        round_0,
        memberId_0,
        choice_0,
        this._pickSaltOf_0(
          round_0,
          this._localSecretKey_0(
            context,
            partialProofData
          )
        )
      );
      assert(
        this._equal_1(
          recomputed_0,
          _descriptor_3.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(9n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_3.toValue(publicMemberId_0),
                      alignment: _descriptor_3.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "reveal does not match the seal"
      );
      const publicChoice_0 = choice_0;
      queryLedgerState(
        context,
        partialProofData,
        [
          { idx: {
            cached: false,
            pushPath: true,
            path: [
              {
                tag: "value",
                value: {
                  value: _descriptor_2.toValue(10n),
                  alignment: _descriptor_2.alignment()
                }
              }
            ]
          } },
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(publicMemberId_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(publicChoice_0),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } },
          { ins: { cached: true, n: 1 } }
        ]
      );
      if (this._equal_2(publicChoice_0, 1n)) {
        const tmp_0 = 1n;
        queryLedgerState(
          context,
          partialProofData,
          [
            { idx: {
              cached: false,
              pushPath: true,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(12n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { addi: { immediate: parseInt(valueToBigInt(
              {
                value: _descriptor_5.toValue(tmp_0),
                alignment: _descriptor_5.alignment()
              }.value
            )) } },
            { ins: { cached: true, n: 1 } }
          ]
        );
      } else {
        const tmp_1 = 1n;
        queryLedgerState(
          context,
          partialProofData,
          [
            { idx: {
              cached: false,
              pushPath: true,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(11n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { addi: { immediate: parseInt(valueToBigInt(
              {
                value: _descriptor_5.toValue(tmp_1),
                alignment: _descriptor_5.alignment()
              }.value
            )) } },
            { ins: { cached: true, n: 1 } }
          ]
        );
      }
      return [];
    }
    _settle_0(context, partialProofData, result_0) {
      this._assertSteward_0(context, partialProofData);
      assert(
        _descriptor_1.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(0n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value) === 1,
        "no open slip to settle"
      );
      assert(
        this._blockTimeGte_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(4n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "cannot settle before reveals close"
      );
      assert(
        this._blockTimeLt_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(5n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "the settle window has closed"
      );
      const publicResult_0 = result_0;
      assert(
        publicResult_0 < 2n,
        "outcome must be 0 (No) or 1 (Yes)"
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(13n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(publicResult_0),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(0n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_1.toValue(2),
              alignment: _descriptor_1.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      return [];
    }
    _dispute_0(context, partialProofData) {
      assert(
        _descriptor_1.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(0n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value) === 2,
        "there is no recorded outcome to dispute"
      );
      assert(
        this._blockTimeLt_0(
          context,
          partialProofData,
          _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(6n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value)
        ),
        "the dispute window has closed"
      );
      const memberId_0 = this._memberIdOf_0(this._localSecretKey_0(
        context,
        partialProofData
      ));
      const publicMemberId_0 = memberId_0;
      assert(
        _descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(8n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "not in this crew"
      );
      assert(
        _descriptor_4.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(9n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { push: {
              storage: false,
              value: StateValue.newCell({
                value: _descriptor_3.toValue(publicMemberId_0),
                alignment: _descriptor_3.alignment()
              }).encode()
            } },
            "member",
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value),
        "did not seal this round"
      );
      const tmp_0 = 3n;
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(13n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(tmp_0),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(14n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_3.toValue(publicMemberId_0),
              alignment: _descriptor_3.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      queryLedgerState(
        context,
        partialProofData,
        [
          { push: {
            storage: false,
            value: StateValue.newCell({
              value: _descriptor_2.toValue(0n),
              alignment: _descriptor_2.alignment()
            }).encode()
          } },
          { push: {
            storage: true,
            value: StateValue.newCell({
              value: _descriptor_1.toValue(3),
              alignment: _descriptor_1.alignment()
            }).encode()
          } },
          { ins: { cached: false, n: 1 } }
        ]
      );
      return [];
    }
    _equal_0(x0, y0) {
      if (!x0.every((x, i) => y0[i] === x)) {
        return false;
      }
      return true;
    }
    _equal_1(x0, y0) {
      if (!x0.every((x, i) => y0[i] === x)) {
        return false;
      }
      return true;
    }
    _equal_2(x0, y0) {
      if (x0 !== y0) {
        return false;
      }
      return true;
    }
  };
  function ledger(stateOrChargedState) {
    const state = stateOrChargedState instanceof StateValue ? stateOrChargedState : stateOrChargedState.state;
    const chargedState = stateOrChargedState instanceof StateValue ? new ChargedState(stateOrChargedState) : stateOrChargedState;
    const context = {
      currentQueryContext: new QueryContext(chargedState, dummyContractAddress()),
      costModel: CostModel.initialCostModel()
    };
    const partialProofData = {
      input: { value: [], alignment: [] },
      output: void 0,
      publicTranscript: [],
      privateTranscriptOutputs: []
    };
    return {
      get status() {
        return _descriptor_1.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(0n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get stewardAuth() {
        return _descriptor_3.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(1n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get questionCommit() {
        return _descriptor_3.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(2n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get sealDeadline() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(3n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get revealDeadline() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(4n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get settleDeadline() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(5n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get disputeDeadline() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(6n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get roundId() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(7n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value);
      },
      crew: {
        isEmpty(...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`isEmpty: expected 0 arguments, received ${args_0.length}`);
          }
          return _descriptor_4.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(8n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              "size",
              { push: {
                storage: false,
                value: StateValue.newCell({
                  value: _descriptor_0.toValue(0n),
                  alignment: _descriptor_0.alignment()
                }).encode()
              } },
              "eq",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        size(...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`size: expected 0 arguments, received ${args_0.length}`);
          }
          return _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(8n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              "size",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        member(...args_0) {
          if (args_0.length !== 1) {
            throw new CompactError(`member: expected 1 argument, received ${args_0.length}`);
          }
          const elem_0 = args_0[0];
          if (!(elem_0.buffer instanceof ArrayBuffer && elem_0.BYTES_PER_ELEMENT === 1 && elem_0.length === 32)) {
            typeError(
              "member",
              "argument 1",
              "slip.compact line 151 char 1",
              "Bytes<32>",
              elem_0
            );
          }
          return _descriptor_4.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(8n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { push: {
                storage: false,
                value: StateValue.newCell({
                  value: _descriptor_3.toValue(elem_0),
                  alignment: _descriptor_3.alignment()
                }).encode()
              } },
              "member",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        [Symbol.iterator](...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`iter: expected 0 arguments, received ${args_0.length}`);
          }
          const self_0 = state.asArray()[8];
          return self_0.asMap().keys().map((elem) => _descriptor_3.fromValue(elem.value))[Symbol.iterator]();
        }
      },
      seals: {
        isEmpty(...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`isEmpty: expected 0 arguments, received ${args_0.length}`);
          }
          return _descriptor_4.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(9n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              "size",
              { push: {
                storage: false,
                value: StateValue.newCell({
                  value: _descriptor_0.toValue(0n),
                  alignment: _descriptor_0.alignment()
                }).encode()
              } },
              "eq",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        size(...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`size: expected 0 arguments, received ${args_0.length}`);
          }
          return _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(9n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              "size",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        member(...args_0) {
          if (args_0.length !== 1) {
            throw new CompactError(`member: expected 1 argument, received ${args_0.length}`);
          }
          const key_0 = args_0[0];
          if (!(key_0.buffer instanceof ArrayBuffer && key_0.BYTES_PER_ELEMENT === 1 && key_0.length === 32)) {
            typeError(
              "member",
              "argument 1",
              "slip.compact line 154 char 1",
              "Bytes<32>",
              key_0
            );
          }
          return _descriptor_4.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(9n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { push: {
                storage: false,
                value: StateValue.newCell({
                  value: _descriptor_3.toValue(key_0),
                  alignment: _descriptor_3.alignment()
                }).encode()
              } },
              "member",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        lookup(...args_0) {
          if (args_0.length !== 1) {
            throw new CompactError(`lookup: expected 1 argument, received ${args_0.length}`);
          }
          const key_0 = args_0[0];
          if (!(key_0.buffer instanceof ArrayBuffer && key_0.BYTES_PER_ELEMENT === 1 && key_0.length === 32)) {
            typeError(
              "lookup",
              "argument 1",
              "slip.compact line 154 char 1",
              "Bytes<32>",
              key_0
            );
          }
          return _descriptor_3.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(9n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_3.toValue(key_0),
                      alignment: _descriptor_3.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value);
        },
        [Symbol.iterator](...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`iter: expected 0 arguments, received ${args_0.length}`);
          }
          const self_0 = state.asArray()[9];
          return self_0.asMap().keys().map((key) => {
            const value = self_0.asMap().get(key).asCell();
            return [_descriptor_3.fromValue(key.value), _descriptor_3.fromValue(value.value)];
          })[Symbol.iterator]();
        }
      },
      reveals: {
        isEmpty(...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`isEmpty: expected 0 arguments, received ${args_0.length}`);
          }
          return _descriptor_4.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(10n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              "size",
              { push: {
                storage: false,
                value: StateValue.newCell({
                  value: _descriptor_0.toValue(0n),
                  alignment: _descriptor_0.alignment()
                }).encode()
              } },
              "eq",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        size(...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`size: expected 0 arguments, received ${args_0.length}`);
          }
          return _descriptor_0.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(10n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              "size",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        member(...args_0) {
          if (args_0.length !== 1) {
            throw new CompactError(`member: expected 1 argument, received ${args_0.length}`);
          }
          const key_0 = args_0[0];
          if (!(key_0.buffer instanceof ArrayBuffer && key_0.BYTES_PER_ELEMENT === 1 && key_0.length === 32)) {
            typeError(
              "member",
              "argument 1",
              "slip.compact line 158 char 1",
              "Bytes<32>",
              key_0
            );
          }
          return _descriptor_4.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(10n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { push: {
                storage: false,
                value: StateValue.newCell({
                  value: _descriptor_3.toValue(key_0),
                  alignment: _descriptor_3.alignment()
                }).encode()
              } },
              "member",
              { popeq: {
                cached: true,
                result: void 0
              } }
            ]
          ).value);
        },
        lookup(...args_0) {
          if (args_0.length !== 1) {
            throw new CompactError(`lookup: expected 1 argument, received ${args_0.length}`);
          }
          const key_0 = args_0[0];
          if (!(key_0.buffer instanceof ArrayBuffer && key_0.BYTES_PER_ELEMENT === 1 && key_0.length === 32)) {
            typeError(
              "lookup",
              "argument 1",
              "slip.compact line 158 char 1",
              "Bytes<32>",
              key_0
            );
          }
          return _descriptor_2.fromValue(queryLedgerState(
            context,
            partialProofData,
            [
              { dup: { n: 0 } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_2.toValue(10n),
                      alignment: _descriptor_2.alignment()
                    }
                  }
                ]
              } },
              { idx: {
                cached: false,
                pushPath: false,
                path: [
                  {
                    tag: "value",
                    value: {
                      value: _descriptor_3.toValue(key_0),
                      alignment: _descriptor_3.alignment()
                    }
                  }
                ]
              } },
              { popeq: {
                cached: false,
                result: void 0
              } }
            ]
          ).value);
        },
        [Symbol.iterator](...args_0) {
          if (args_0.length !== 0) {
            throw new CompactError(`iter: expected 0 arguments, received ${args_0.length}`);
          }
          const self_0 = state.asArray()[10];
          return self_0.asMap().keys().map((key) => {
            const value = self_0.asMap().get(key).asCell();
            return [_descriptor_3.fromValue(key.value), _descriptor_2.fromValue(value.value)];
          })[Symbol.iterator]();
        }
      },
      get tallyNo() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(11n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value);
      },
      get tallyYes() {
        return _descriptor_0.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(12n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: true,
              result: void 0
            } }
          ]
        ).value);
      },
      get outcome() {
        return _descriptor_2.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(13n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      },
      get disputedBy() {
        return _descriptor_3.fromValue(queryLedgerState(
          context,
          partialProofData,
          [
            { dup: { n: 0 } },
            { idx: {
              cached: false,
              pushPath: false,
              path: [
                {
                  tag: "value",
                  value: {
                    value: _descriptor_2.toValue(14n),
                    alignment: _descriptor_2.alignment()
                  }
                }
              ]
            } },
            { popeq: {
              cached: false,
              result: void 0
            } }
          ]
        ).value);
      }
    };
  }
  var _emptyContext = {
    currentQueryContext: new QueryContext(new ContractState().data, dummyContractAddress())
  };
  var _dummyContract = new Contract({
    localSecretKey: (...args) => void 0,
    localPick: (...args) => void 0
  });
  var pureCircuits = {
    memberIdOf: (...args_0) => {
      if (args_0.length !== 1) {
        throw new CompactError(`memberIdOf: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
      }
      const sk_0 = args_0[0];
      if (!(sk_0.buffer instanceof ArrayBuffer && sk_0.BYTES_PER_ELEMENT === 1 && sk_0.length === 32)) {
        typeError(
          "memberIdOf",
          "argument 1",
          "slip.compact line 219 char 1",
          "Bytes<32>",
          sk_0
        );
      }
      return _dummyContract._memberIdOf_0(sk_0);
    },
    pickSaltOf: (...args_0) => {
      if (args_0.length !== 2) {
        throw new CompactError(`pickSaltOf: expected 2 arguments (as invoked from Typescript), received ${args_0.length}`);
      }
      const round_0 = args_0[0];
      const sk_0 = args_0[1];
      if (!(typeof round_0 === "bigint" && round_0 >= 0n && round_0 <= 18446744073709551615n)) {
        typeError(
          "pickSaltOf",
          "argument 1",
          "slip.compact line 244 char 1",
          "Uint<0..18446744073709551616>",
          round_0
        );
      }
      if (!(sk_0.buffer instanceof ArrayBuffer && sk_0.BYTES_PER_ELEMENT === 1 && sk_0.length === 32)) {
        typeError(
          "pickSaltOf",
          "argument 2",
          "slip.compact line 244 char 1",
          "Bytes<32>",
          sk_0
        );
      }
      return _dummyContract._pickSaltOf_0(round_0, sk_0);
    },
    pickCommitment: (...args_0) => {
      if (args_0.length !== 4) {
        throw new CompactError(`pickCommitment: expected 4 arguments (as invoked from Typescript), received ${args_0.length}`);
      }
      const round_0 = args_0[0];
      const memberId_0 = args_0[1];
      const choice_0 = args_0[2];
      const salt_0 = args_0[3];
      if (!(typeof round_0 === "bigint" && round_0 >= 0n && round_0 <= 18446744073709551615n)) {
        typeError(
          "pickCommitment",
          "argument 1",
          "slip.compact line 257 char 1",
          "Uint<0..18446744073709551616>",
          round_0
        );
      }
      if (!(memberId_0.buffer instanceof ArrayBuffer && memberId_0.BYTES_PER_ELEMENT === 1 && memberId_0.length === 32)) {
        typeError(
          "pickCommitment",
          "argument 2",
          "slip.compact line 257 char 1",
          "Bytes<32>",
          memberId_0
        );
      }
      if (!(typeof choice_0 === "bigint" && choice_0 >= 0n && choice_0 <= 255n)) {
        typeError(
          "pickCommitment",
          "argument 3",
          "slip.compact line 257 char 1",
          "Uint<0..256>",
          choice_0
        );
      }
      if (!(salt_0.buffer instanceof ArrayBuffer && salt_0.BYTES_PER_ELEMENT === 1 && salt_0.length === 32)) {
        typeError(
          "pickCommitment",
          "argument 4",
          "slip.compact line 257 char 1",
          "Bytes<32>",
          salt_0
        );
      }
      return _dummyContract._pickCommitment_0(
        round_0,
        memberId_0,
        choice_0,
        salt_0
      );
    }
  };
  var contractReferenceLocations = { tag: "publicLedgerArray", indices: {} };
  return __toCommonJS(index_exports);
})();
