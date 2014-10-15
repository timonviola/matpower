function t_islands(quiet)
%T_ISLANDS  Tests for FIND_ISLANDS, EXTRACT_ISLANDS and CONNECTED_COMPONENTS.

%   MATPOWER
%   $Id$
%   by Ray Zimmerman, PSERC Cornell
%   Copyright (c) 2012, 2014 by Power System Engineering Research Center (PSERC)
%
%   This file is part of MATPOWER.
%   See http://www.pserc.cornell.edu/matpower/ for more info.
%
%   MATPOWER is free software: you can redistribute it and/or modify
%   it under the terms of the GNU General Public License as published
%   by the Free Software Foundation, either version 3 of the License,
%   or (at your option) any later version.
%
%   MATPOWER is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
%   GNU General Public License for more details.
%
%   You should have received a copy of the GNU General Public License
%   along with MATPOWER. If not, see <http://www.gnu.org/licenses/>.
%
%   Additional permission under GNU GPL version 3 section 7
%
%   If you modify MATPOWER, or any covered work, to interface with
%   other modules (such as MATLAB code and MEX-files) available in a
%   MATLAB(R) or comparable environment containing parts covered
%   under other licensing terms, the licensors of MATPOWER grant
%   you additional permission to convey the resulting work.

if nargin < 1
    quiet = 0;
end

num_tests = 229;

t_begin(num_tests, quiet);

%% define named indices into data matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;

if quiet
    verbose = 0;
else
    verbose = 0;
end

%% load cases
casenames = {'case118', 'case30', 'case14', 'case9'};
n = length(casenames);
for k = 1:n
    mpc{k} = loadcase(casenames{k});
    
    %% add bus names
    nb = size(mpc{k}.bus, 1);
    mpc{k}.bus_name = cell(nb, 1);
    for b = 1:nb
        mpc{k}.bus_name{b} = sprintf('bus %d', mpc{k}.bus(b, BUS_I));
    end
    
    %% add gen emission.rate, genid
    ng = size(mpc{k}.gen, 1);
    mpc{k}.emission.rate = zeros(ng, 3);
    mpc{k}.genid1 = zeros(ng, 2);
    mpc{k}.genid2 = zeros(2, ng);
    for g = 1:ng
        mpc{k}.emission.rate(g,:) = g * [1 2 3];
        mpc{k}.genid1(g, :) = [g  mpc{k}.gen(g, PMAX)];
        mpc{k}.genid2(:, g) = [g; mpc{k}.gen(g, PMAX)];
    end
end
custom.bus{1} = { 'bus_name' };
custom.gen{1} = { {'emission', 'rate'}, 'genid1' };
custom.gen{2} = { 'genid2' };
custom.branch{2} = { 'nonexistent' };

% verbose = 2;
mpopt = mpoption('out.all', 0, 'verbose', verbose);

%% run individual AC PFs
t = 'individual PFs : success ';
for k = 1:n
    r{k} = runpf(mpc{k}, mpopt);
    t_ok(r{k}.success, sprintf('%s %d', t, k));
end

%% stack the systems into one
for k = 1:n
    offset = k * 1000;
    mpc{k}.bus(:, BUS_I)    = mpc{k}.bus(:, BUS_I)  + offset;
    mpc{k}.gen(:, GEN_BUS)  = mpc{k}.gen(:, GEN_BUS)    + offset;
    mpc{k}.branch(:, F_BUS) = mpc{k}.branch(:, F_BUS)   + offset;
    mpc{k}.branch(:, T_BUS) = mpc{k}.branch(:, T_BUS)   + offset;
end

mpc0 = mpc{1};
for k = 2:n
    mpc0.bus        = [mpc0.bus;    mpc{k}.bus];
    mpc0.gen        = [mpc0.gen;    mpc{k}.gen];
    mpc0.branch     = [mpc0.branch; mpc{k}.branch];
    mpc0.gencost    = [mpc0.gencost; mpc{k}.gencost];
    
    mpc0.bus_name       = [mpc0.bus_name;       mpc{k}.bus_name];
    mpc0.emission.rate  = [mpc0.emission.rate;  mpc{k}.emission.rate];
    mpc0.genid1         = [mpc0.genid1;         mpc{k}.genid1];
    mpc0.genid2         = [mpc0.genid2          mpc{k}.genid2];
end

%% run AC OPF
t = 'joint PF : ';
r0 = runpf(mpc0, mpopt);
t_ok(r0.success, [t 'success']);

refs = find(mpc0.bus(:, BUS_TYPE) == REF);
for k = 1:n
    ref = find(mpc{k}.bus(:, BUS_TYPE) == REF);
    gref0 = find(  mpc0.gen(:, GEN_BUS) ==   mpc0.bus(refs(k), BUS_I));
    gref  = find(mpc{k}.gen(:, GEN_BUS) == mpc{k}.bus(    ref, BUS_I));

    t_is(mpc0.gen(gref0, PG), mpc{k}.gen(gref, PG), 8, sprintf('%sslack PG %d', t, k));
end

%% extract the islands
t = 'mpcs = extract_islands(mpc) : ';
mpc1 = extract_islands(mpc0);
t_ok(iscell(mpc1), [t 'iscell(mpcs)']);
t_is(length(mpc1), n, 10, [t 'length(mpcs) == n']);
for k = 1:n
    t_is(mpc1{k}.bus,     mpc{k}.bus,     10, sprintf('%smpcs{%d}.bus', t, k));
    t_is(mpc1{k}.gen,     mpc{k}.gen,     10, sprintf('%smpcs{%d}.gen', t, k));
    t_is(mpc1{k}.branch,  mpc{k}.branch,  10, sprintf('%smpcs{%d}.branch', t, k));
    t_is(mpc1{k}.gencost, mpc{k}.gencost, 10, sprintf('%smpcs{%d}.gencost', t, k));
    t_is(length(mpc1{k}.bus_name), length(mpc0.bus_name), 10, sprintf('%smpcs{%d}.bus_name dim', t, k));
    t_is(mpc1{k}.emission.rate, mpc0.emission.rate,     10, sprintf('%smpcs{%d}.emission.rate', t, k));
    t_is(mpc1{k}.genid1,        mpc0.genid1,            10, sprintf('%smpcs{%d}.genid1', t, k));
    t_is(mpc1{k}.genid2,        mpc0.genid2,            10, sprintf('%smpcs{%d}.genid2', t, k));
end

%% extract the islands, with custom fields
t = 'mpcs = extract_islands(mpc, [], custom) : ';
mpc1 = extract_islands(mpc0, [], custom);
%mpc1 = extract_islands(mpc0, {}, [], custom);  %% this should work too
t_ok(iscell(mpc1), [t 'iscell(mpcs)']);
t_is(length(mpc1), n, 10, [t 'length(mpcs) == n']);
for k = 1:n
    t_is(mpc1{k}.bus,     mpc{k}.bus,     10, sprintf('%smpcs{%d}.bus', t, k));
    t_is(mpc1{k}.gen,     mpc{k}.gen,     10, sprintf('%smpcs{%d}.gen', t, k));
    t_is(mpc1{k}.branch,  mpc{k}.branch,  10, sprintf('%smpcs{%d}.branch', t, k));
    t_is(mpc1{k}.gencost, mpc{k}.gencost, 10, sprintf('%smpcs{%d}.gencost', t, k));
    t_is(length(mpc1{k}.bus_name), length(mpc{k}.bus_name), 10, sprintf('%smpcs{%d}.bus_name dim', t, k));
    t_is(mpc1{k}.emission.rate, mpc{k}.emission.rate,     10, sprintf('%smpcs{%d}.emission.rate', t, k));
    t_is(mpc1{k}.genid1,        mpc{k}.genid1,            10, sprintf('%smpcs{%d}.genid1', t, k));
    t_is(mpc1{k}.genid2,        mpc{k}.genid2,            10, sprintf('%smpcs{%d}.genid2', t, k));
end

%% extract single island
t = 'mpc3 = extract_islands(mpc, 3) : ';
mpc3 = extract_islands(mpc0, 3);
t_ok(isstruct(mpc3), [t 'isstruct(mpc3)']);
k = 3;
t_is(mpc3.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc3.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc3.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc3.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc3.bus_name), length(mpc0.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc3.emission.rate, mpc0.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc3.genid1,        mpc0.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc3.genid2,        mpc0.genid2,            10, sprintf('%smpc%d.genid2', t, k));

%% extract single island, with custom fields
t = 'mpc3 = extract_islands(mpc, 3, custom) : ';
mpc3 = extract_islands(mpc0, 3, custom);
t_ok(isstruct(mpc3), [t 'isstruct(mpc3)']);
k = 3;
t_is(mpc3.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc3.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc3.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc3.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc3.bus_name), length(mpc{k}.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc3.emission.rate, mpc{k}.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc3.genid1,        mpc{k}.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc3.genid2,        mpc{k}.genid2,            10, sprintf('%smpc%d.genid2', t, k));

%% find the islands
t = 'groups = find_islands(mpc) : ';
groups = find_islands(mpc0);
t_ok(iscell(groups), [t 'iscell(groups)']);
t_is(length(groups), n, 10, [t 'length(groups) == n']);
base = 0;
for k = 1:n
    nbk = size(mpc{k}.bus, 1);
    t_is(groups{k}, base+(1:nbk), 10, [t k]);
    base = base + nbk;
end

%% extract the islands
t = 'mpcs = extract_islands(mpc, groups) : ';
mpc2 = extract_islands(mpc0, groups);
t_ok(iscell(mpc2), [t 'iscell(mpcs)']);
t_is(length(mpc2), n, 10, [t 'length(mpcs) == n']);
for k = 1:n
    t_is(mpc2{k}.bus,     mpc{k}.bus,     10, sprintf('%smpcs{%d}.bus', t, k));
    t_is(mpc2{k}.gen,     mpc{k}.gen,     10, sprintf('%smpcs{%d}.gen', t, k));
    t_is(mpc2{k}.branch,  mpc{k}.branch,  10, sprintf('%smpcs{%d}.branch', t, k));
    t_is(mpc2{k}.gencost, mpc{k}.gencost, 10, sprintf('%smpcs{%d}.gencost', t, k));
    t_is(length(mpc2{k}.bus_name), length(mpc0.bus_name), 10, sprintf('%smpcs{%d}.bus_name dim', t, k));
    t_is(mpc2{k}.emission.rate, mpc0.emission.rate,     10, sprintf('%smpcs{%d}.emission.rate', t, k));
    t_is(mpc2{k}.genid1,        mpc0.genid1,            10, sprintf('%smpcs{%d}.genid1', t, k));
    t_is(mpc2{k}.genid2,        mpc0.genid2,            10, sprintf('%smpcs{%d}.genid2', t, k));
end

%% extract the islands, with custom fields
t = 'mpcs = extract_islands(mpc, groups, [], custom) : ';
mpc2 = extract_islands(mpc0, groups, [], custom);
t_ok(iscell(mpc2), [t 'iscell(mpcs)']);
t_is(length(mpc2), n, 10, [t 'length(mpcs) == n']);
for k = 1:n
    t_is(mpc2{k}.bus,     mpc{k}.bus,     10, sprintf('%smpcs{%d}.bus', t, k));
    t_is(mpc2{k}.gen,     mpc{k}.gen,     10, sprintf('%smpcs{%d}.gen', t, k));
    t_is(mpc2{k}.branch,  mpc{k}.branch,  10, sprintf('%smpcs{%d}.branch', t, k));
    t_is(mpc2{k}.gencost, mpc{k}.gencost, 10, sprintf('%smpcs{%d}.gencost', t, k));
    t_is(length(mpc2{k}.bus_name), length(mpc{k}.bus_name), 10, sprintf('%smpcs{%d}.bus_name dim', t, k));
    t_is(mpc2{k}.emission.rate, mpc{k}.emission.rate,     10, sprintf('%smpcs{%d}.emission.rate', t, k));
    t_is(mpc2{k}.genid1,        mpc{k}.genid1,            10, sprintf('%smpcs{%d}.genid1', t, k));
    t_is(mpc2{k}.genid2,        mpc{k}.genid2,            10, sprintf('%smpcs{%d}.genid2', t, k));
end

%% extract single island
t = 'mpc4 = extract_islands(mpc, groups, 4) : ';
mpc4 = extract_islands(mpc0, groups, 4);
t_ok(isstruct(mpc4), [t 'isstruct(mpc4)']);
k = 4;
t_is(mpc4.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc4.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc4.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc4.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc4.bus_name), length(mpc0.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc4.emission.rate, mpc0.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc4.genid1,        mpc0.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc4.genid2,        mpc0.genid2,            10, sprintf('%smpc%d.genid2', t, k));

%% extract single island, with custom fields
t = 'mpc4 = extract_islands(mpc, groups, 4, custom) : ';
mpc4 = extract_islands(mpc0, groups, 4, custom);
t_ok(isstruct(mpc4), [t 'isstruct(mpc4)']);
k = 4;
t_is(mpc4.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc4.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc4.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc4.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc4.bus_name), length(mpc{k}.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc4.emission.rate, mpc{k}.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc4.genid1,        mpc{k}.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc4.genid2,        mpc{k}.genid2,            10, sprintf('%smpc%d.genid2', t, k));

%% extract 2 islands as single case
t = 'mpc13 = extract_islands(mpc, [1;3]) : ';
mpc13 = extract_islands(mpc0, [1;3]);
mpc1 = extract_islands(mpc13, 1);
mpc3 = extract_islands(mpc13, 2);
k = 1;
t_is(mpc1.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc1.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc1.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc1.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc1.bus_name), length(mpc0.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc1.emission.rate, mpc0.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc1.genid1,        mpc0.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc1.genid2,        mpc0.genid2,            10, sprintf('%smpc%d.genid2', t, k));
k = 3;
t_is(mpc3.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc3.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc3.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc3.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc3.bus_name), length(mpc0.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc3.emission.rate, mpc0.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc3.genid1,        mpc0.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc3.genid2,        mpc0.genid2,            10, sprintf('%smpc%d.genid2', t, k));

%% extract 2 islands as single case, with custom fields
t = 'mpc13 = extract_islands(mpc, [1;3], custom) : ';
mpc13 = extract_islands(mpc0, [1;3], custom);
mpc1 = extract_islands(mpc13, 1, custom);
mpc3 = extract_islands(mpc13, 2, custom);
k = 1;
t_is(mpc1.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc1.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc1.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc1.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc1.bus_name), length(mpc{k}.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc1.emission.rate, mpc{k}.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc1.genid1,        mpc{k}.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc1.genid2,        mpc{k}.genid2,            10, sprintf('%smpc%d.genid2', t, k));
k = 3;
t_is(mpc3.bus,     mpc{k}.bus,     10, sprintf('%smpc%d.bus', t, k));
t_is(mpc3.gen,     mpc{k}.gen,     10, sprintf('%smpc%d.gen', t, k));
t_is(mpc3.branch,  mpc{k}.branch,  10, sprintf('%smpc%d.branch', t, k));
t_is(mpc3.gencost, mpc{k}.gencost, 10, sprintf('%smpc%d.gencost', t, k));
t_is(length(mpc3.bus_name), length(mpc{k}.bus_name), 10, sprintf('%smpc%d.bus_name dim', t, k));
t_is(mpc3.emission.rate, mpc{k}.emission.rate,     10, sprintf('%smpc%d.emission.rate', t, k));
t_is(mpc3.genid1,        mpc{k}.genid1,            10, sprintf('%smpc%d.genid1', t, k));
t_is(mpc3.genid2,        mpc{k}.genid2,            10, sprintf('%smpc%d.genid2', t, k));

t = '[groups, isolated] = find_islands(mpc) : ';
mpc = loadcase('case30');
mpc.branch(25, BR_STATUS) = 0;  %% 10-20
mpc.branch(26, BR_STATUS) = 0;  %% 10-17
mpc.branch(13, BR_STATUS) = 0;  %%  9-11, isolates bus 11
mpc.branch(15, BR_STATUS) = 0;  %%  4-12, last tie between areas 1 and 2
mpc.branch(32, BR_STATUS) = 0;  %% 23-24, last tie between areaa 2 and 3
mpc.branch(21, BR_STATUS) = 0;  %% 16-17, isolates bus 17
mpc.branch(24, BR_STATUS) = 0;  %% 19-20, isolates bus 20
mpc.branch(12, BR_STATUS) = 0;  %%  6-10, tie between areas 1 and 3
mpc.branch(14, BR_STATUS) = 0;  %%  9-10, tie between areas 1 and 3
mpc.branch(36, BR_STATUS) = 0;  %% 27-28, tie between areas 1 and 3
[groups, isolated] = find_islands(mpc);
t_ok(iscell(groups), [t 'iscell(groups)']);
t_is(length(groups), 3, 10, [t 'length(groups) == 3']);
t_is(isolated, [11 17 20], 10, [t 'isolated']);
t_is(sort([11     groups{1}]), find(mpc.bus(:, BUS_AREA) == 1)', 10, [t 'groups{1}']);
t_is(             groups{2},   find(mpc.bus(:, BUS_AREA) == 3)', 10, [t 'groups{2}']);
t_is(sort([17 20  groups{3}]), find(mpc.bus(:, BUS_AREA) == 2)', 10, [t 'groups{3}']);

%% extract 2 islands as single case
t = 'mpc1 = extract_islands(mpc, ''all'') : ';
mpc1 = extract_islands(mpc, 'all');
ibr = find( ~ismember(mpc.branch(:, F_BUS), isolated) & ...
            ~ismember(mpc.branch(:, T_BUS), isolated) );
ig = find( ~ismember(mpc.gen(:, GEN_BUS), isolated) );
mpc2 = mpc;
mpc2.bus(isolated, :) = [];
mpc2.branch = mpc.branch(ibr, :);
mpc2.gen    = mpc.gen(ig, :);
mpc2.gencost = mpc.gencost(ig, :);
t_is(mpc1.bus,     mpc2.bus,     10, sprintf('%smpc.bus', t));
t_is(mpc1.gen,     mpc2.gen,     10, sprintf('%smpc.gen', t));
t_is(mpc1.branch,  mpc2.branch,  10, sprintf('%smpc.branch', t));
t_is(mpc1.gencost, mpc2.gencost, 10, sprintf('%smpc.gencost', t));

t_end;
