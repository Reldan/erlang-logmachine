%%%-------------------------------------------------------------------
%%% @author <vjache@gmail.com>
%%% @copyright (C) 2011, Vyacheslav Vorobyov.  All Rights Reserved.
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%% http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% @doc
%%%    TODO: Document it.
%%% @end
%%% Created : Nov 06, 2011
%%%-------------------------------------------------------------------------------
-module(logmachine_emlocator_srv).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% External exports
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-import(logmachine_util,[make_name/1]).

-record(state, {em_name,instance}).

%% ====================================================================
%% External functions
%% ====================================================================


%% ====================================================================
%% Server functions
%% ====================================================================
start_link(InstanceName) ->
    SrvName=make_name([InstanceName, locator, srv]),
    gen_server:start_link({local, SrvName}, ?MODULE, {locator,InstanceName}, []).

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init({locator, InstanceName}) ->
    EventManagerName=logmachine_app:get_instance_env(InstanceName, locate_em, InstanceName),
    erlang:process_flag(trap_exit, true),
    install_event_handlers(node(),EventManagerName, InstanceName),
    ok=net_kernel:monitor_nodes(true, [{node_type, visible}, nodedown_reason]),
    {ok, #state{instance=InstanceName,em_name=EventManagerName}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(Msg, State) ->
    handle_info(Msg, State).

handle_info({nodeup, Node, _InfoList}, #state{instance=InstanceName,em_name=EventManagerName}=State) ->
    install_event_handlers(Node,EventManagerName, InstanceName),
    {noreply, State};
handle_info({nodedown, _Node, _InfoList}, State) ->
    % Node down report
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------
install_event_handlers(Node, EventManagerName, InstanceName) ->
    try gen_event:which_handlers({EventManagerName, Node}),
        HandlerModule=logmachine_event_handler,
        upload_module(Node, HandlerModule),
        ok=gen_event:add_sup_handler(
             {EventManagerName, Node}, % EventMgrRef
             {HandlerModule, node()},  % Handler
             logmachine_receiver_srv:get_global_alias(InstanceName)) % Args
    catch _: noproc -> ok end.
upload_module(Node, _Mod) when Node==node() ->
    ok;
upload_module(Node, Mod) ->
    case code:get_object_code(Mod) of
        {_Module, Bin, Fname} ->
            case rpc:call(Node, code, load_binary, [Mod, Fname, Bin]) of
                {error, Reason} -> throw({cant_upload_module, Node, Mod, Reason});
                {badrpc, Reason} -> throw({cant_upload_module, Node, Mod, Reason});
                {module, Mod} ->
                    ok
            end;
        error ->
            throw({cant_upload_module, Node, Mod, {error, {'code:get_object_code', [Mod]}}})
    end.
