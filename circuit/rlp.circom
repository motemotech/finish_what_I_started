pragma circom 2.0.2;

include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/multiplexer.circom";

template Num2Bits(n) {
    signal input in;
    signal output out[n];
    var lc1 = 0;

    var e2 = 1;
    for (var i = 0; i < n; i++) {
        out[i] <-- (in >> i) & 1;
        out[i] * (out[i] - 1) === 0;
        lc1 += out[i] * e2;
        e2 = e2 + e2;
    }
    lc1 === in;
}

// This stackoverflow is really great to understand what is going on here.
// https://stackoverflow.com/questions/73323540/confused-about-circom-lessthan-implementation
template LessThan(n) {
    assert(n <= 252);
    signal input in[2];
    signal output out;

    component n2b = Num2Bits(n+1);

    n2b.in <== in[0] + (1<<n) - in[1];

    out <== 1 - n2b.out[n];
}

template IsZero() {
    signal input in;
    signal output out;

    signal inv;

    inv <-- in != 0 ? 1/in : 0;

    out <== -in * inv + 1;
    in*out === 0;
}

template IsEqual() {
    signal input in[2];
    signal output out;

    component isz = IsZero();

    in[1] - in[0] ==> isz.in;

    isz.out ==> out;
}

template EscalarProduct(w) {
    signal input in1[w];
    signal input in2[w];
    signal output out;
    signal aux[w];
    var lc = 0;
    for (var i = 0; i < w; i++) {
        aux[i] <== in1[i] * in2[i];
        lc = lc + aux[i];
    }
    out <== lc;
}

template Decoder(w) {
    signal input inp;
    signal output out[w];
    signal output success;
    var lc = 0;

    for (var i = 0; i < w; i++) {
        out[i] <== (inp == i) ? 1 : 0;
        out[i] * (inp - 1) === 0;
        lc = lc + out[i];
    }

    lc ==> success;
    success * (success - 1) === 0;
}

template Multiplexer(wIn, nIn) {
    signal input inp[nIn][wIn];
    signal input sel;
    signal output out[wIn];
    component dec = Decoder(nIn);
    component ep[wIn];

    for (var k = 0; k < wIn; k++) {
        ep[k] = EscalarProduct(nIn);
    }

    sel ==> dec.inp;
    for (var j = 0; j < wIn; j++) {
        for (var k = 0; k < nIn; k++) {
            inp[k][j] ==> ep[j].in1[k];
            dec.out[k] ==> ep[j].in2[k];
        }
        ep[j].out ==> out[j];
    }
    dec.success === 1;
}

template RlpArrayPrefix() {
    signal input in[2];
    signal output isBig;
    signal output prefixOrTotalHexLen;
    signal output isValid;

    log(333333300004);
    log(in[0]);
    log(in[1]);

    component n2b1 = Num2Bits(4);
    component n2b2 = Num2Bits(4);
    n2b1.in = in[0];
    n2b2.in = in[1];

    // it starts with < 'c', then invalid
    component lt1 = LessThan(4);
    lt1.in[0] <== in[0];
    lt1.in[1] <== 12;

    // if starts with 'f'
    component eq = IsEqual();
    eq.in[0] <== in[0];
    eq.in[1] <== 15;

    component lt2 = LessThan(4);
    lt2.in[0] <== in[1];
    lt2.in[1] <== 8;

    isBig <== eq.out * (1 - lt2.out);

    // [c0, f7] or [f8, ff]
    var prefixVal = 16 * in[0] + in[1];
    isValid <== 1 - lt1.out;
    signal lenTemp;
    lenTemp <== 2 * (prefixVal - 16 * 12) + 2 * isBig * (16 * 12 - 16 * 15 - 7);
    prefixOrTotalHexLen <== isValid * lenTemp;

    log(isBig);
    log(prefixOrTotalHexLen);
    log(isValid);
}

template RlpArrayCheck(maxHexLen, nFields, arrayPrefixMaxHexLen, fieldMinHexLen, fieldMaxHexLen) {
    signal input in[maxHexLen];

    signal output out;
    signal output fieldHexLen[nFields];
    signal output fields[nFields][maxHexLen];
    signal output totalRlpHexLen;

    log(333333300006);
    log(maxHexLen);
    log(nFields);
    log(arrayPrefixMaxHexLen);
    for (var idx = 0; idx < nFields; idx++) {
        log(fieldMinHexLen[idx]);
    }
    for (var idx = 0; idx < nFields; idx++) {
        log(fieldMaxHexLen[idx]);
    }
    for (var idx = 0; idx < maxHexLen; idx++) {
        log(in[idx]);
    }

    component rlpArrayPrefix = RlpArrayPrefix();
    rlpArrayPrefix.in[0] = in[0];
    rlpArrayPrefix.in[1] = in[1];

    signal arrayRlpPrefix1HexLen;
    arrayRlpPrefix1HexLen <== rlpArrayPrefix.isBig * rlpArrayPrefix.prefixOrTotalHexLen;

    component totalArray = Multiplexer(1, arrayPrefixMaxHexLen);
    var temp = 0;
    for (var idx = 0; idx < arrayPrefixMaxHexLen; idx++) {
        temp = 16 * temp + in[2 + idx];
        totalArray.inp[idx][0] <== temp;
    }
    totalArray.sel <== rlpArrayPrefix.isBig * (arrayRlpPrefix1HexLen - 1);
    
    signal totalArrayHexLen;
    totalArrayHexLen <== rlpArrayPrefix.prefixOrTotalHexLen + rlpArrayPrefix.isBig * (2 * totalArray.out[0] - rlpArrayPrefix.prefixOrTotalHexLen);

    totalRlpHexLen <== 2 + arrayRlpPrefix1HexLen + totalArrayHexLen;

    component shiftToFieldRlps[nFields];
    component shiftToField[nFields];
    component fieldPrefix[nFields];

    signal fieldRlpPrefix1HexLen[nFields];
    component fieldHexLenMulti[nFields];
    signal field_temp[nFields];

    for (var idx = 0; idx < nFields; idx++) {
        var lenPrefixMaxHexs = 2 * (log_ceil(fieldMaxHexLen[idx]) \ 8 + 1);
        if (idx == 0) {
            shiftToFieldRlps[idx] = ShiftLeft(maxHexLen, 0, 2 + arrayPrefixMaxHexLen);
        } else {
            shiftToFieldRlps[idx] = ShiftLeft(maxHexLen, fieldMinHexLen[idx - 1], fieldMaxHexLen[idx - 1]);
        }
        shiftToField[idx] = ShiftLeft(maxHexLen, 0, lenPrefixMaxHexs);
        fieldPrefix[idx] = RlpFieldPrefix();

        if (idx == 0) {
            for (var j = 0; j < maxHexLen; j++) {
                shiftToFieldRlps[idx].in[j] <== in[j];
            }
            shiftToFieldRlps[idx].shift <== 2 + arrayRlpPrefix1HexLen;
        } else {
            for (var j = 0; j < maxHexLen; j++) {
                shiftToFieldRlps[idx].in[j] <== shiftToField[idx - 1].out[j];
            }
            shiftToFieldRlps[idx].shift <== fieldMinHexLen[idx - 1];
        }
        fieldPrefix[idx].in[0] <== shiftToFieldRlps[idx].out[0];
        fieldPrefix[idx].in[1] <== shiftToFieldRlps[idx].out[1];

        fieldRlpPrefix1HexLen[idx] <== fieldPrefix[idx].isBig * fieldPrefix[idx].prefixOrTotalHexLen;

        fieldHexLenMulti[idx] = Multiplexer(1, fieldMaxHexLen[idx]);
        var temp = 0;
        for (var j = 0; j < lenPrefixMaxHexs; j++) {
            temp = 16 * temp + shiftToFieldRlps[idx].out[2 + j];
            fieldHexLenMulti[idx].inp[j][0] <== temp;
        }
        fieldHexLenMulti[idx].sel <== fieldPrefix[idx].isBig * (fieldRlpPrefix1HexLen[idx] - 1);
        var temp2 = (2 * fieldHexLenMulti[idx].out[0] - fieldPrefix[idx].prefixOrTotalHexLen);
        field_temp[idx] <== fieldPrefix[idx].prefixOrTotalHexLen + fieldPrefix[idx].isBig * temp2;
        fieldHexLen[idx] <== field_temp[idx] + 2 * fieldPrefix[idx].isLiteral - field_temp[idx] * fieldPrefix[idx].isLiteral;

        for (var j = 0; j < maxHexLen; j++) {
            fields[idx][j] <== shiftToField[idx].out[j];
        }
    }

    var check = rlpArrayPrefix.isValid;
    for (var idx = 0; idx < nFields; idx++) {
        check = check * fieldPrefix[idx].isValid;
    }

    var letSum = 0;
    for (var idx = 0; idx < nFields; idx++) {
        letSum = letSum + 2 - 2 * fieldPrefix[idx].isLiteral + fieldRlpPrefix1HexLen[idx] + fieldHexLen[idx];
    }
    component lenCheck = IsEqual();
    outCheck.in[0] <== check + lenCheck.out;
    outCheck.in[1] <== nFields + 2;

    out <== outCheck.out;

    log(out);
    log(totalRlpHexLen);
    for (var idx = 0; idx < nFields; idx++) {
        log(fieldHexLen[idx]);
    }
    for (var idx = 0; idx < nFields; idx++) {
        for (var j = 0; j < maxHexLen; j++) {
            log(fields[idx][j]);
        }       
    }
}