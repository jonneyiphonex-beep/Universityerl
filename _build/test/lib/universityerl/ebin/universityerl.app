{application,universityerl,
             [{description,"University academic administration system"},
              {vsn,"1.0.0"},
              {registered,[universityerl_sup]},
              {mod,{universityerl_app,[]}},
              {applications,[kernel,stdlib,crypto,cowboy,jsx]},
              {env,[{port,8080},{web_dir,"web"}]},
              {modules,[universityerl_app,universityerl_http,
                        universityerl_store,universityerl_sup]}]}.
