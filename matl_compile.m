function S = matl_compile(S, F, L, pOutFile, cOutFile, verbose, isMatlab, verNum, useTags, online)
%
% MATL compiler. Compiles into MATLAB code.
% Input: struct array with parsed statements.
% Produces output file with the MATLAB code.

% Each MATLAB line is a string in cell array C.

% Variables related to MATL are uppercase: STACK, S_IN, S_OUT, CB_G--CB_M.

% The MATL stack (variable 'STACK') is implemented in MATLAB as a dynamic-size cell, for two
% reasons:
%  - simplicity of the code
%  - that way the variable representing the stack can be viewed directly
%    wen debugging
%
% The multi-level clipboard L (variable 'CB_L') is a cell array of cells. The "outer" cells
% refer to clipboard levels. The "inner cells" refer to copied elements within that clipboard 
% level. CB_L is a dynamic cell array: outer cells are created on the fly
% when clipboard levels are copied to.
%
% Luis Mendo

global indStepComp C implicitInputBlock

indStepComp = 4;

compat_folder = 'compatibility';

if verbose
    disp('  Generating compiled code')
end

% For replacing letters in literal arrays:
arrayReplaceOrig = {'O' 'l' 'H' 'I' 'K' 'A' 'B' 'C' 'D' 'E' 'X'  'a'  'b'  'c'  'd'  'F'     'T'    'P'  'Y'   'N'   'J'  'G'};
 arrayReplaceOrigMat = cell2mat(arrayReplaceOrig); % same as a matrix. Above cells must contain only single letters
arrayReplaceDest = {'0' '1' '2' '3' '4' '5' '6' '7' '8' '9' '10' '-1' '-2' '-3' '-4' 'false' 'true' 'pi' 'inf' 'NaN' 'j' '-1j'};
% spaces in arrayReplaceDest are added later
arrayAllowMat = 'ej';

Fsource = {F.source}; % this field of `F` will be used often

% Possible improvement: preallocate for greater speed, and modify
% appendLines so that C doesn't dynamically grow
C = {}; % Cell array of strings. Each cell contains a line of compiled (MATLAB) code

if useTags
    strongBegin = '<strong>';
    strongEnd = '</strong>';
else
    strongBegin = '';
    strongEnd = '';
end

% Define blocks of code that will be reused
implicitInputBlock = {...
    'if ~isempty(nin) && (numel(STACK)+nin(1)<1)' ...
    'implInput = {};' ...
    'for k = 1:1-numel(STACK)-nin(1)' ...
    'implInput{k} = input(implicitInputPrompt,''s'');' ...
    'valid = isempty(regexp(implInput{k}, ''^[^'''']*(''''[^'''']*''''[^'''']*)*[a-df-ik-zA-EG-MOQ-SU-XZ]'', ''once'')) && isempty(regexp(implInput{k}, ''^[^'''']*(''''[^'''']*''''[^'''']*)*[a-zA-Z]{2}'', ''once''));' ...
    'assert(valid, ''MATL:runner'', ''MATL run-time error: input not allowed'')' ...
    'if isempty(implInput{k}), implInput{end} = []; else implInput{k} = eval(implInput{k}); end' ...
    'end' ...
    'STACK = [implInput STACK];' ...
    'CB_G = [CB_G implInput];' ...
    'clear implInput k' ...
    'end'};
    % We don't update CB_M. This implicit input is not considered a
    % function call, and would have 0 inputs anyway

% Include function header
[~, name] = fileparts(cOutFile);
appendLines(['function ' name], 0)

% Include date and time
appendLines(['% Generated by MATL compiler, ' datestr(now)], 0)

% Set initial conditions.
appendLines('', 0)
appendLines('% Set initial conditions', 0)
appendLines('tic;', 0)
appendLines('warningState = warning;', 0);
appendLines('format compact; format long; warning(''off'',''all''); close all', 0) % clc
appendLines('defaultColorMap = get(0, ''DefaultFigureColormap'');', 0)
appendLines('set(0, ''DefaultFigureColormap'', gray(256));', 0)
if isMatlab && exist('rng', 'file') % recent Matlab version
    appendLines('rng(''shuffle'')', 0)
elseif isMatlab % old Matlab version
    appendLines('rand(''seed'',sum(clock)); randn(''seed'',sum(clock))', 0);
% else % Octave: seeds are set randomly automatically by Octave
end
if ~online
    appendLines('delete inout; diary off; delete defout; diary defout', 0)
end
% For user inputs or inputs to "str2num"
appendLines('F = false; T = true; P = pi; Y = inf; N = NaN;', 0)
% Constants to be used by function code
appendLines('numCbM = 4;', 0); % number of levels in clipboard M
if online
    appendLines('defaultInputPrompt = '''';', 0);
    appendLines('implicitInputPrompt = '''';', 0);
else
    appendLines('defaultInputPrompt = ''> '';', 0);
    appendLines('implicitInputPrompt = ''> '';', 0);
end
appendLines('replaceBySpace = char([0:7 14:31]);', 0); % these characters will be replaced by space
% Predefine literals for functions
if ~isempty(S)
    plf = cellstr(char(bsxfun(@plus, 'X0', [floor(0:.1:2.9).' repmat((0:9).',3,1)]))).'; % {'X0'...'Z9'}
    str = intersect(plf, {S.source}); % only those functions that are actually used
    for n = 1:numel(str);
        appendLines(['preLit.' str{n} '.key = ' mat2str(L.(str{n}).key) '; '], 0)
        appendLines(['preLit.' str{n} '.val = {' sprintf('%s ', L.(str{n}).val{:}) '};'], 0)
    end
end
% Initiallize stack (empty)
appendLines('STACK = {};', 0)
% Initiallize function input and output specifications (to empty).
appendLines('S_IN = ''def''; S_OUT = ''def'';', 0)
% Initiallize clipboards. Clipboards H--L are implemented directly as variables.
% Clipboard L is implemented as a cell array, where each cell is one clipboard
% "level".
appendLines('CB_H = { 2 }; CB_I = { 3 }; CB_J = { 1j }; CB_K = { 4 }; CB_L = { {[1 2 1j]} {[2 2 1j]} {[1 1j-1]} {[2 1j]} {[1 0]} {[2 1j-1]} {[2 3 1]} {[3 1 2]} {[1 1j]} {[1j -1 1]} {3600} {86400} {1440} {[31 28 31 30 31 30 31 31 30 31 30 31]} {[31 29 31 30 31 30 31 31 30 31 30 31]} {0.5772156649015328606} {(sqrt(5)+1)/2} };', 0)
% Initiallize automatic clipboards. Clipboard L is implemented as a cell
% array, where each cell is one clipboard "level" containing one input. It
% is initially empty.
appendLines('CB_G = { }; CB_M = repmat({{}},1,numCbM);', 0)
% Read input file, if present. Don't do it in online compiler
if ~online
    appendLines('if exist(''defin'',''file''), fid = fopen(''defin'',''r''); STACK{end+1} = reshape(fread(fid,inf,''*char''),1,[]); fclose(fid); end', 0)
end

% Process each MATL statement. Precede with a commented line containing the MATL
% statement. Add a field in S indicating the line of that MATL statement in
% the compiled MATLAB file. Generate corresponding MATLAB code.

for n = 1:numel(S)
    newLines = {};
    appendLines('', 0)
    if S(n).implicit
        comment = [S(n).source ' (implicit)'];
    else
        comment = [S(n).source];
    end
    appendLines(['% ' comment], S(n).nesting) % include MATL statement as a comment
    S(n).compileLine = numel(C); % take note of starting line for MATL statement in compiled code
    switch S(n).type
        case {'literal.number', 'literal.colonArray.numeric', 'literal.string', 'literal.colonArray.char'}
            appendLines(['STACK{end+1} = ' S(n).source ';'], S(n).nesting)
        case {'literal.array', 'literal.cellArray'}
            x = S(n).source;
            % Replace recognized letters by numbers with spaces
            % for k = 1:numel(arrayReplaceOrig) % We remove this because Octave can't handle the regex (Matlab can)
            %     orig = ['(?<=^[^'']*(''[^'']*''[^'']*)*)' arrayReplaceOrig{k}];
            %     dest = [' ' arrayReplaceDest{k} ' '];
            %     x = regexprep(x, orig, dest);
            % end
            w = find(~mod(cumsum(x==''''),2) & isletter(x)); % positions of x where replacing
            % should take place: letters that have an even number of preceding quotes
            lastArrayAllowed = -1; % initiallize. Index of last allowed letter found
            for k = w(end:-1:1) % inverse order because x will grow
                [~, ind] = find(x(k)==arrayReplaceOrigMat); % x(k) is one of the letters to be replaced
                if ~isempty(ind)
                    x = [ x(1:k-1) ' ' arrayReplaceDest{ind} ' ' x(k+1:end) ];
                elseif any(x(k)==arrayAllowMat) % x(k) is allowed, as long as it's not contiguous with another
                    if k==lastArrayAllowed-1; % we are going backwards. Contiguous means this
                        error('MATL:compiler', 'Content not allowed in MATL array literal');
                    else
                        lastArrayAllowed = k; % update
                    end
                else % equivalently: elseif ~any(x(k)==arrayAllowMat)
                    error('MATL:compiler', 'Content not allowed in MATL array literal');
                end
                % We cannot (easily) check with a regexp after letter replacing,
                % because there will possibly be things like 'pi', 'true' etc.
                % So we do it in the code above: an error is issued if any unrecognized letter is found,
                % or if two recognized letters are contiguous
            end
            % Now generate compiled line
            appendLines(['STACK{end+1} = ' x ';'], S(n).nesting)
        case 'literal.logicalRowArray'
            lit = strrep(strrep(S(n).source,'T','true,'),'F','false,');
            lit = ['[' lit(1:end-1) ']'];
            appendLines(['STACK{end+1} = ' lit ';'], S(n).nesting)
        case 'metaFunction.inSpec'
            appendLines('nin = 0;', S(n).nesting);
            appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
            appendLines('S_IN = STACK{end}; STACK(end) = [];', S(n).nesting)
            appendLines('if isempty(S_IN), S_IN = ''def''; end', S(n).nesting)
        case 'metaFunction.outSpec'
            appendLines('nin = 0;', S(n).nesting);
            appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
            appendLines('S_OUT = STACK{end}; STACK(end) = [];', S(n).nesting)
            appendLines('if isempty(S_OUT), S_OUT = ''def''; end', S(n).nesting)
        case 'metaFunction.altInOut'
            appendLines('S_IN = ''alt''; S_OUT = ''alt'';', S(n).nesting)
        case 'controlFlow.for'
            appendLines('nin = 0;', S(n).nesting);
            appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
            newLines{1} = sprintf('in = STACK{end}; STACK(end) = []; indFor%i = 0;', S(n).nesting);
            newLines{2} = sprintf('for varFor%i = in', S(n).nesting);
            appendLines(newLines, S(n).nesting)
            % newLines{1} = sprintf('STACK{end+1} = varFor%i;', S(n).nesting);
            newLines = sprintf('indFor%i = indFor%i+1;', S(n).nesting, S(n).nesting);
            appendLines(newLines, S(n).nesting+1)
        case 'controlFlow.doWhile' % '`'
            newLines = { sprintf('indDoWhile%i = 0;', S(n).nesting) ...
                sprintf('condDoWhile%i = true;', S(n).nesting) ...
                sprintf('while condDoWhile%i', S(n).nesting) };
            appendLines(newLines, S(n).nesting)
            newLines = sprintf('indDoWhile%i = indDoWhile%i+1;', S(n).nesting, S(n).nesting);
            appendLines(newLines, S(n).nesting+1)
        case 'controlFlow.while' % 'X`'
            appendLines('nin = 0;', S(n).nesting);
            appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
            newLines = { sprintf('indWhile%i = 0;', S(n).nesting) ...
                sprintf('condWhile%i = STACK{end}; if ~isreal(condWhile%i), condWhile%i = real(condWhile%i); end', S(n).nesting, S(n).nesting, S(n).nesting, S(n).nesting) ...
                'STACK(end) = [];' ... 
                sprintf('while condWhile%i', S(n).nesting) };
            appendLines(newLines, S(n).nesting)
            newLines = sprintf('indWhile%i = indWhile%i+1;', S(n).nesting, S(n).nesting);
            appendLines(newLines, S(n).nesting+1)
        case 'controlFlow.if' % '?'
            appendLines('nin = 0;', S(n).nesting);
            appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
            newLines = { 'in = STACK{end}; STACK(end) = []; if ~isreal(in), in = real(in); end' ...
                'if in' };
            appendLines(newLines, S(n).nesting);
        case 'controlFlow.else' % '}'
            appendLines('else', S(n).nesting)
        case 'controlFlow.finally' % '}'
            if strcmp(S(S(n).from).type, 'controlFlow.doWhile')
                appendLines('nin = 0;', S(n).nesting);
                appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
                newLines = { sprintf('condDoWhile%i = STACK{end}; if ~isreal(condDoWhile%i), condDoWhile%i = real(condDoWhile%i); end', S(n).nesting, S(n).nesting, S(n).nesting, S(n).nesting) ...
                    'STACK(end) = [];' ...
                    sprintf('if condDoWhile%i, else', S(n).nesting) }; % We use 'if condDoWhile%i, else' rather than 'if ~condDoWhile%i'
                    % so as to reproduce Matlab's behaviour when the condition is an array ('if ~condDoWhile%i' wouldn't do)
                appendLines(newLines, S(n).nesting);
            elseif strcmp(S(S(n).from).type, 'controlFlow.while')
                appendLines('nin = 0;', S(n).nesting);
                appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
                newLines = { sprintf('condWhile%i = STACK{end}; if ~isreal(condWhile%i), condWhile%i = real(condWhile%i); end', S(n).nesting, S(n).nesting, S(n).nesting, S(n).nesting) ...
                    'STACK(end) = [];' ...
                    sprintf('if condWhile%i, else', S(n).nesting) };
                appendLines(newLines, S(n).nesting);
            else
                error('MATL:compiler:internal', 'MATL internal error while compiling statement %s%s%s: unrecognized loop type', strongBegin, S(n).source, strongEnd)
            end
        case 'controlFlow.end' % ']'
            if strcmp(S(S(n).from).type, 'controlFlow.doWhile')
                if ~isfield(S(S(n).from), 'finally') || isempty(S(S(n).from).finally)
                    appendLines('nin = 0;', S(n).nesting);
                    appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
                    newLines = { sprintf('condDoWhile%i = STACK{end}; if ~isreal(condDoWhile%i), condDoWhile%i = real(condDoWhile%i); end', S(n).nesting, S(n).nesting, S(n).nesting, S(n).nesting) ...
                        'STACK(end) = [];' ...
                        'end' }; % end the "while"
                    appendLines(newLines, S(n).nesting);
                else % the condition was already obtained at the "finally" statement
                    appendLines('end', S(n).nesting); % end the "if" that implements the "finally"
                    appendLines('end', S(n).nesting); % end the "while"
                end
                appendLines(sprintf('clear indDoWhile%i', S(n).nesting), S(n).nesting)
            elseif strcmp(S(S(n).from).type, 'controlFlow.while')
                if ~isfield(S(S(n).from), 'finally') || isempty(S(S(n).from).finally)
                    appendLines('nin = 0;', S(n).nesting);
                    appendLines(implicitInputBlock, S(n).nesting); % code block for implicit input
                    newLines = { sprintf('condWhile%i = STACK{end}; if ~isreal(condWhile%i), condWhile%i = real(condWhile%i); end', S(n).nesting, S(n).nesting, S(n).nesting, S(n).nesting) ...
                        'STACK(end) = [];' ...
                        'end' }; % end the "while"
                    appendLines(newLines, S(n).nesting);
                else % the condition was already obtained at the "finally" statement
                    appendLines('end', S(n).nesting); % end the "if" that implements the "finally"
                    appendLines('end', S(n).nesting); % end the "while"
                end
                appendLines(sprintf('clear indWhile%i', S(n).nesting), S(n).nesting)
            elseif strcmp(S(S(n).from).type, 'controlFlow.for')
                newLines = { 'end' ...
                    sprintf('clear indFor%i', S(n).nesting) };
                appendLines(newLines, S(n).nesting)
            elseif strcmp(S(S(n).from).type, 'controlFlow.if')
                newLines = 'end';
                appendLines(newLines, S(n).nesting);
            else
                error('MATL:compiler:internal', 'MATL internal error while compiling statement %s%s%s', strongBegin, S(n).source, strongEnd)
            end
        case 'controlFlow.break'
            appendLines('break', S(n).nesting)
        case 'controlFlow.continue'
            appendLines('continue', S(n).nesting)
        case 'controlFlow.forValue'
            k = S(S(n).from).nesting;
            appendLines(sprintf('STACK{end+1} = varFor%i;', k), S(n).nesting)
        case 'controlFlow.doWhileIndex'
            k = S(S(n).from).nesting;
            appendLines(sprintf('STACK{end+1} = indDoWhile%i;', k), S(n).nesting)
        case 'controlFlow.whileIndex'
            k = S(S(n).from).nesting;
            appendLines(sprintf('STACK{end+1} = indWhile%i;', k), S(n).nesting)
        case 'controlFlow.forIndex'
            k = S(S(n).from).nesting;
            appendLines(sprintf('STACK{end+1} = indFor%i;', k), S(n).nesting)
        case 'function'
            k = find(strcmp(S(n).source, Fsource), 1); % Fsource is guaranteed to contain unique entries.
            if isempty(k)
                if useTags
                    error('MATL:compiler', 'MATL error while compiling: function %s%s%s in <a href="matlab: opentoline(''%s'', %i)">statement number %i</a> not defined in MATL', strongBegin, S(n).source, strongEnd, pOutFile, n, n)
                else
                    error('MATL:compiler', 'MATL error while compiling: function %s%s%s in statement number %i not defined in MATL', strongBegin, S(n).source, strongEnd, n)
                end
            end
            if online && ~F(k).allowedOnline
                error('MATL:compiler', 'MATL compiler error: function %s not allowed in online compiler', F(k).source)
            end
            appendLines(funWrap(F(k).minIn, F(k).maxIn, F(k).defIn, F(k).altIn, F(k).minOut, F(k).maxOut, F(k).defOut, F(k).altOut, ...
                F(k).consumeInputs, F(k).wrap, F(k).funInClipboard, F(k).body), S(n).nesting)
            C = [C strcat(blanks(indStepComp*S(n).nesting), newLines)];
        otherwise
            error('MATL:compiler:internal', 'MATL internal error while compiling statement %s%s%s: unrecognized statement type', strongBegin, S(n).source, strongEnd)
    end
end

% Set final conditions
appendLines('', 0)
appendLines('% Set final conditions', 0)
appendLines('diary off; warning(warningState);', 0);
appendLines('set(0, ''DefaultFigureColormap'', defaultColorMap);', 0)
appendLines('', 0)
appendLines('end', 0) % close function, in case there are subfunctions

% Define subfunctions for compatibility with Octave
% If any of the names in `fnames` is found, the content of the file
% '..._comp.m' will be included in the compiled file. That '..._comp.m' file may
% contain one or several functions; each of those functions (even if there's only one) should
% have an 'end' statement
if ~isMatlab
    appendLines('', 0)
    appendLines('% Define subfunctions', 0)
    fnames = {'num2str' 'im2col' 'spiral' 'unique' 'union' 'intersect' 'setdiff' 'setxor' 'ismember' ...
        'triu' 'tril' 'randsample' 'nchoosek' 'vpa' 'sum' 'mean' 'diff' 'mod' 'repelem' 'dec2bin' 'dec2base' ...
        'hypergeom' 'disp' 'str2func' 'logical' 'circshift' 'pdist2' 'strsplit' 'max' 'min' 'strncmp' 'round'...
        'datestr' 'regexp' 'regexprep'};
    verNumTh = [4 0 0]; % first version in which a modified function is not needed:
    if (verNum(1)<verNumTh(1)) || ((verNum(1)==verNumTh(1)) && (verNum(2)<verNumTh(2))) || ((verNum(1)==verNumTh(1)) && (verNum(2)==verNumTh(2)) && (verNum(3)<verNumTh(3)))
        fnames = [fnames {'colon'}];
    end
    for n = 1:numel(fnames)
        fname = fnames{n};
        if any(~cellfun(@isempty,strfind(C,fname))) % This may give false positives, but that's not a problem
            fid = fopen([compat_folder filesep fname '_comp.m'], 'r');
            x = reshape(fread(fid,inf,'*char'),1,[]);
            fclose(fid);
            x = regexprep(x, '\r\n', '\n');
            appendLines(x, 0)
            appendLines('', 0)
        end
    end 
end

if verbose
    fprintf('  Writing to file ''%s''\n', cOutFile')
end

% Write to file:

if exist(cOutFile,'file')
    delete(cOutFile) % even though `fwrite` discards the file's previous contents, and there's a `clear`
    % later, I delete the file initially here. I do it just in case: at some point I've
    % seen Octave run an old version of the compiled file after changing the source code (which produces
    % a new compiled file). I think this must a a file cache thing. (Even accidentally deleting a file
    % before attemtping to run it sometimes resulted in a successful run!) I'm not sure how helpful
    % deleting the file will be, though.
end
fid = fopen(cOutFile,'w');
for n = 1:numel(C)
    if ispc % Windows
        linebreak = '\r\n';
    elseif ismac % Mac
        linebreak = '\r';
    elseif isunix % Unix, Linux
        linebreak = '\n';
    else % others. Not sure what to use here
        linebreak = '\r\n';
    end
    fprintf(fid, ['%s' repmat(linebreak,1,n<numel(C))], C{n}); % avoid linebreak in last line
end
fclose(fid);

% Clear file so that the new one will be used
clear(cOutFile)
end

function newLines = funPre(minIn, maxIn, defIn, altIn, minOut, maxOut, defOut, altOut, consume, funInClipboard)
% Code generated at the beginning of functions: check `S_IN` and `S_OUT`,
% define `nout`, get inputs, prepare outputs, consume inputs if applicable.
% `consume` indicates if inputs should be removed from the stack
%   (1) If `nout` is a non-negative number (specified or by default), the function should
% produce that number of outputs. For MATL functions that simply call a MATLAB function,
% this implies calling the MATLAB function with that number of outputs. For MATL functions
% that are implemented "manually", it's their responsibility to produce `nout` outputs.
%   If `n_out` is a logical array, the number of outputs produced by the function
% should be the number of elements in the logical array. At the end (funPost), the
% outputs corresponding to false values will be discarded.
%   (2) For functions for which the default value of S_OUT depends on the
% inputs (cannot be computed at compile-time) and can be computed at
% run-time at the beginning of the function, this default value is
% specified in the function definition file as the appropriate code, in the form of
% a string that will be evaluated at the beginning of the function call.
% That result from string will be assigned to `nout`.
%   (3) For functions for which the default value of S_OUT depends on the inputs
% and is very difficult to compute even at run-time at the beginning of the function,
% a negative number is specified as default value in the function definition file. A negative
% number means "`nout` unspecified, the function will build the variable `out` with the default
% number of outputs as defined by the function, or with `nout` outputs if `nout` is nonnegative".
%   A negative value of the default number of outputs is translated into the appropriate text
% in the help and documentation; different negative values can be used to select that text.
%   If possible, it's probably safer to use method (2) than (3).
global implicitInputBlock
newLines = { sprintf('if strcmp(S_IN,''def''), S_IN = %s; end', defIn) };
if isempty(altIn) && isempty(altOut)
    newLines{end+1} = 'if strcmp(S_IN,''alt''), error(''MATL:runner'', ''MATL run-time error: alternative input/output specification not defined for this function'' ), end';
elseif ~isempty(altIn)
    newLines{end+1} = sprintf('if strcmp(S_IN,''alt''), S_IN = %s; end', altIn);
else
    newLines{end+1} = sprintf('if strcmp(S_IN,''alt''), S_IN = %s; end', defIn);
end
newLines = [newLines, {...
    sprintf('if isnumeric(S_IN) && numel(S_IN) == 1, if S_IN < %s || S_IN > %s, error(''MATL:runner'', ''MATL run-time error: incorrect input specification''), end', minIn, maxIn) ...
    sprintf('elseif islogical(S_IN), if nnz(S_IN) < %s || nnz(S_IN) > %s, error(''MATL:runner'', ''MATL run-time error: incorrect input specification''), end', minIn, maxIn) ...
    'else error(''MATL:runner'', ''MATL run-time error: input specification not recognized''), end' ...
    'if isnumeric(S_IN), nin = -S_IN+1:0; else nin = find(S_IN)-numel(S_IN); end' }];
newLines = [newLines implicitInputBlock]; % code block for implicit input
newLines = [newLines, {'in = STACK(end+nin);'} ];
if funInClipboard
    newLines = [newLines, {'if ~isempty(in), CB_M = [{in} CB_M(1:end-1)]; end'} ];
end
newLines = [newLines, { sprintf('if strcmp(S_OUT,''def''), S_OUT = %s; end', defOut) }];
if isempty(altIn) && isempty(altOut)
    newLines{end+1} = 'if strcmp(S_OUT,''alt''), error(''MATL:runner'', ''MATL run-time error: alternative input/output specification not defined for this function'' ), end';
elseif ~isempty(altOut)
    newLines{end+1} = sprintf('if strcmp(S_OUT,''alt''), S_OUT = %s; end', altOut);
else
    newLines{end+1} = sprintf('if strcmp(S_OUT,''alt''), S_OUT = %s; end', defOut);
end
newLines = [newLines, {...
    sprintf('if isnumeric(S_OUT) && numel(S_OUT) == 1, if S_OUT >= 0 && (S_OUT < %s || S_OUT > 2*(%s)), error(''MATL:runner'', ''MATL run-time error: incorrect output specification''), end', minOut, maxOut) ...
    sprintf('elseif islogical(S_OUT), if numel(S_OUT) < %s || numel(S_OUT) > %s, error(''MATL:runner'', ''MATL run-time error: incorrect output specification''), end', minOut, maxOut) ...
    'else error(''MATL:runner'', ''MATL run-time error: output specification not recognized''), end' ...
    sprintf('if isnumeric(S_OUT) && S_OUT > %s, S_OUT = [false(1,S_OUT-(%s+1)) true]; end', maxOut, maxOut) ...
    'if isnumeric(S_OUT), nout = S_OUT; else nout = numel(S_OUT); end' ...
    'if nout>=0, out = cell(1,nout); end' }];
% 2*(...) because a number in maxOut+1:2*maxOut corresponds to a logical vector with a single true value
% For logical S_IN we use nnz (the inputs are picked from the stack), but
% for logical S_OUT we use numel (the function is called with that many outputs)
if consume
    newLines{end+1} = 'STACK(end+nin) = [];';
end
end

function newLines = funPost
% Code generated at the end of every normal function: get outputs, push
% outputs, delete S_IN and S_OUT. 
newLines = { 'if islogical(S_OUT), out = out(S_OUT); end' ...
    'STACK = [STACK out];' ...
    'S_IN = ''def'';' ...
    'S_OUT = ''def'';' ...
    'clear nin nout in out' };
end

function newLines = funWrap(minIn, maxIn, defIn, altIn, minOut, maxOut, defOut, altOut, consumeInputs, wrap, funInClipboard, body)
% Implements use of stack to get inputs and outputs and realizes function body.
% Specifically, it packs `funPre`, function body and `funPost`.
% This is used for normal, stack-rearranging and clipboard functions.
% Meta-functions don't have this; just the function body.
if funInClipboard && ~wrap
    error('MATL:compiler:internal', 'MATL internal error while compiling: funInClipboard==true with wrap==false not implemented in the compiler. funInClipboard is only handled by funPre, which is only called if wrap==true')
end
if ~iscell(body)
    body = {body}; % convert to 1x1 cell array containing a string
end
if wrap
    newLines = [ funPre(minIn, maxIn, defIn, altIn, minOut, maxOut, defOut, altOut, consumeInputs, funInClipboard) body funPost ];
else
    newLines = body;
end
end

function appendLines(newLines, nesting)
% Appends lines to cell array of MATLAB code.
% `newLines` is a string or a cell array of strings
global indStepComp
global C
if ~iscell(newLines), newLines = {newLines}; end % string: convert to 1x1 cell array containing a string
newLines = strcat({blanks(indStepComp*nesting)}, newLines);
C(end+(1:numel(newLines))) = newLines;
end

