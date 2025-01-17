open Cmdliner
open Printf
open Config

module CommandLine = struct
  let owner_id =
    let doc = "Gitlab Owner Id" in
    Arg.(
      required
      & opt (some string) None
      & info [ "o"; "owner" ] ~docv:"OWNER" ~doc)

  let owner_name =
    let doc = "Gitlab Ownername" in
    Arg.(
      required
      & opt (some string) None
      & info [ "n"; "owner-name" ] ~docv:"OWNER_NAME" ~doc)

  let api =
    let doc = "The GitLab API endpoint to send the HTTP request to." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"ENDPOINT" ~doc)

  let merge_request_id =
    let doc = "Merge Request Id" in
    Arg.(
      required
      & opt (some string) None
      & info [ "m"; "merge-request-id" ] ~docv:"MERGE_REQUEST_ID" ~doc)

  let project_id =
    let doc = "Project Id" in
    Arg.(
      required
      & opt (some int) None
      & info [ "p"; "project-id" ] ~docv:"PROJECT_ID" ~doc)

  let project_name =
    let doc = "The repository name on GitLab." in
    Arg.(
      required & pos 0 (some string) None & info [] ~docv:"PROJECT_NAME" ~doc)

  let commit_sha =
    let doc = "A commit SHA or branch name (default: \"HEAD\")." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"COMMIT" ~doc)

  let project_description =
    let doc = "A short description of the GitLab repository." in
    Arg.(
      required
      & opt (some string) None
      & info [ "d"; "description" ] ~docv:"PROJECT_DESCRIPTION" ~doc)

  let json =
    let doc = "Print output as formatted json" in
    Arg.(value & opt bool false & info [ "json" ] ~doc)

  let verbose =
    let doc = "Print detailed report of all status checks and their URLs." in
    Arg.(value & opt bool false & info [ "v"; "verbose" ] ~doc)

  let state =
    let doc = "CI State" in
    let commit_status_status =
      Arg.enum
        [
          ("pending", `Pending);
          ("running", `Running);
          ("success", `Success);
          ("failed", `Failed);
          ("cancelled", `Cancelled);
        ]
    in
    Arg.(
      required
      & pos 1 (some commit_status_status) (Some `Pending)
      & info [] ~docv:"STATE" ~doc)
end

(* Non-zero exit with error message *)
let exit_with str =
  eprintf "%s" str;
  exit 1

let envs = Gitlab.Env.envs

let user_cmd =
  let user_list user =
    let cmd =
      let open Gitlab in
      let open Monad in
      User.by_id ~id:user () >>~ fun user ->
      return @@ printf "%s\n" user.Gitlab_t.user_username
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "Display user name and id." in
  let info = Cmd.info ~envs ~doc "user-list" in
  let term = Term.(const user_list $ CommandLine.owner_id) in
  Cmd.v info term

let user_name_cmd =
  let user_list name json =
    let cmd name =
      let open Gitlab in
      let open Monad in
      User.by_name ~name () >|~ fun users ->
      if json then
        printf "%s" (Yojson.Basic.prettify (Gitlab_j.string_of_users users))
      else
        List.iter
          (fun user ->
            printf "%s:%i\n" user.Gitlab_t.user_short_username
              user.Gitlab_t.user_short_id)
          users
    in
    Lwt_main.run @@ Gitlab.Monad.run (cmd name)
  in
  let doc = "Display users by name and id." in
  let info = Cmd.info ~envs ~doc "user-name" in
  let term = Term.(const user_list $ CommandLine.owner_name $ CommandLine.json) in
  Cmd.v info term

let user_projects_cmd =
  let user_projects_list id =
    let cmd =
      let open Gitlab in
      let open Monad in
      User.projects ~id () >|~ fun projects ->
      List.iter
        (fun project -> printf "%s\n" project.Gitlab_t.project_short_name)
        projects
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "List public projects owned by the user." in
  let info = Cmd.info ~envs ~doc "user-projects"  in
  let term = Term.(const user_projects_list $ CommandLine.owner_id) in
  Cmd.v info term

let user_events_cmd config =
  let user_projects_list id =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      User.events ~token:config.token ~id () >|~ fun events ->
      printf "%s\n" (Yojson.Basic.prettify @@ Gitlab_j.string_of_events events)
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "List all user events." in
  let info = Cmd.info ~envs ~doc "user-events" in
  let term =  Term.(const user_projects_list $ CommandLine.owner_id) in
  Cmd.v info term

let merge_requests_cmd config =
  let merge_requests_list () =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      let* mr = return (User.merge_requests ~token:config.token ()) in
      Stream.iter
        (fun merge_request ->
          printf "#%i %s\n" merge_request.Gitlab_t.merge_request_id
            merge_request.Gitlab_t.merge_request_title;
          return ())
        mr
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "List user's merge requests." in
  let info = Cmd.info ~envs ~doc "merge-requests" in
  let term = Term.(const merge_requests_list $ const ()) in
  Cmd.v info term

let status_checks_cmd config =
  let status_checks project_id =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      Project.ExternalStatusCheck.checks ~token:config.token ~project_id ()
      >|~ fun x ->
      List.iter
        (fun check ->
          printf "%s\t%s\t%i\n" check.Gitlab_t.external_status_check_name
            check.Gitlab_t.external_status_check_external_url
            check.Gitlab_t.external_status_check_id)
        x
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "List external status checks." in
  let info = Cmd.info ~envs ~doc "status-checks" in
  let term = Term.(const status_checks $ CommandLine.project_id) in
  Cmd.v info term

let project_create_cmd config =
  let project_create name description =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      Project.create ~token:config.token ~name ~description () >|~ fun p ->
      printf "%s\n" (Yojson.Basic.prettify (Gitlab_j.string_of_project_short p))
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "Creates a new project owned by the authenticated user." in
  let info = Cmd.info ~envs ~doc "project-create" in
  let term = Term.(const project_create $ CommandLine.project_name $ CommandLine.project_description) in
  Cmd.v info term

let ci_status_cmd config =
  let ci_status project_id sha _verbose =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      return @@ Project.Commit.statuses ~token:config.token ~project_id ~sha ()
      >>= fun statuses ->
      let* results = Stream.to_list statuses in
      return
      @@
      match List.length results > 0 with
      | true ->
          List.iter
            (fun status -> printf "%s\n" status.Gitlab_t.commit_status_status)
            results
      | false -> printf "failure\n"
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "List build status of a commit." in
  let info = Cmd.info ~envs ~doc "ci-status" in
  let term = Term.(const ci_status $ CommandLine.project_id $ CommandLine.commit_sha $ CommandLine.verbose) in
  Cmd.v info term

let project_branches_cmd config =
  let project_branches project_id =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      let* branches =
        return @@ Project.Branch.branches ~token:config.token ~project_id ()
      in
      Stream.iter
        (fun branch -> return @@ printf "%s\n" branch.Gitlab_t.branch_full_name)
        branches
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "List branches for a project." in
  let info = Cmd.info ~envs ~doc "branch" in
  let term = Term.(const project_branches $ CommandLine.project_id) in
  Cmd.v info term

let ci_status_set_cmd config =
  let ci_status project_id sha state =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      let new_status =
        {
          Gitlab_t.state;
          ref_name = None;
          name = None;
          target_url = None;
          pipeline_id = None;
          coverage = None;
          description = None;
        }
      in
      Project.Commit.status ~token:config.token ~project_id ~sha new_status ()
      >|~ fun status ->
      printf "%s\n"
        (Yojson.Basic.prettify (Gitlab_j.string_of_commit_status status))
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "Set or update the build status of a commit." in
  let info = Cmd.info ~envs ~doc "set-ci-status" in
  let term = Term.(const ci_status $ CommandLine.project_id $ CommandLine.commit_sha $ CommandLine.state) in
  Cmd.v info term

let api_cmd config =
  let api uri_str =
    let cmd =
      let open Gitlab in
      let open Monad in
      let config = config () in
      let uri = Uri.of_string uri_str in
      API.get ~token:config.token ~uri (fun body -> Lwt.return (Yojson.Basic.from_string body))
      >|~ fun json -> printf "%s" (Yojson.Basic.pretty_to_string json)
    in
    Lwt_main.run @@ Gitlab.Monad.run cmd
  in
  let doc = "Low-level GitLab API request interface." in
  let info = Cmd.info ~doc ~envs "api" in
  let term = Term.(const api $ CommandLine.api) in
  Cmd.v info term

let cmds =
  let doc = "make git easier with GitLab" in
  let default = Term.(ret (const (`Help (`Pager, None)))) in
  let man =
      [
        `S "DESCRIPTION";
        `P
          "Lab is a tool that wraps git in order to extend it with extra \
           functionality that makes it better when working with GitLab.";
        `S "BUGS";
        `P "<https://github.com/tmcgilchrist/ocaml-gitlab/issues>";
        `S "AUTHORS";
        `P "<https://github.com/tmcgilchrist/ocaml-gitlab>";
      ] in
  let info = Cmd.info ~envs "lab" ~version:"0.1" ~doc ~man in
  let config = Config.from_file in
  Cmd.group ~default info
  [
    user_cmd;
    user_name_cmd;
    user_projects_cmd;
    api_cmd config;
    merge_requests_cmd config;
    status_checks_cmd config;
    user_events_cmd config;
    project_create_cmd config;
    ci_status_cmd config;
    ci_status_set_cmd config;
    project_branches_cmd config;
  ]

let () =
  exit @@ Cmd.eval ~catch:true cmds
