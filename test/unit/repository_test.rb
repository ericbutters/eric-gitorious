# encoding: utf-8
#--
#   Copyright (C) 2012 Gitorious AS
#   Copyright (C) 2009 Nokia Corporation and/or its subsidiary(-ies)
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

require File.dirname(__FILE__) + "/../test_helper"
require "ostruct"

class RepositoryTest < ActiveSupport::TestCase
  def new_repos(opts={})
    Repository.new({
      :name => "foo",
      :project => projects(:johans),
      :user => users(:johan),
      :owner => users(:johan)
    }.merge(opts))
  end

  def setup
    @repository = new_repos
    FileUtils.mkdir_p(@repository.full_repository_path, :mode => 0755)
  end

  def teardown
    clear_message_queue
  end

  should_validate_presence_of :user_id, :name, :owner_id
  should_validate_uniqueness_of :hashed_path
  should_validate_uniqueness_of :name, :scoped_to => :project_id, :case_sensitive => false

  should_have_many :hooks, :dependent => :destroy

  should "only accept names with alphanum characters in it" do
    @repository.name = "foo bar"
    assert !@repository.valid?, "valid? should be false"

    @repository.name = "foo!bar"
    assert !@repository.valid?, "valid? should be false"

    @repository.name = "foobar"
    assert @repository.valid?

    @repository.name = "foo42"
    assert @repository.valid?
  end

  should "has a unique name within a project" do
    @repository.save
    repos = new_repos(:name => "FOO")
    assert !repos.valid?, "valid? should be false"
    assert_not_nil repos.errors.on(:name)

    assert new_repos(:project => projects(:moes)).valid?
  end

  should "not have a reserved name" do
    repo = new_repos(:name => Gitorious::Reservations.repository_names.first.dup)
    repo.valid?
    assert_not_nil repo.errors.on(:name)
    RepositoriesController.action_methods.each do |action|
      repo.name = action.dup
      repo.valid?
      assert_not_nil repo.errors.on(:name), "fail on #{action}"
    end
  end

  context "git urls" do
    setup do
      @host_with_user = "#{GitoriousConfig['gitorious_user']}@#{GitoriousConfig['gitorious_host']}"
      @host = "#{GitoriousConfig['gitorious_host']}"
    end

    should "has a gitdir name" do
      assert_equal "#{@repository.project.slug}/foo.git", @repository.gitdir
    end

    should "has a push url" do
      assert_equal "#{@host_with_user}:#{@repository.project.slug}/foo.git", @repository.push_url
    end

    should "has a clone url" do
      assert_equal "git://#{@host}/#{@repository.project.slug}/foo.git", @repository.clone_url
    end

    should "has a http url" do
      assert_equal "#{GitoriousConfig['scheme']}://git.#{@host}/#{@repository.project.slug}/foo.git", @repository.http_clone_url
    end

    should "use the real http cloning URL" do
      old_value = Site::HTTP_CLONING_SUBDOMAIN
      silence_warnings do
        Site::HTTP_CLONING_SUBDOMAIN = "whatever"
      end
      assert_equal "#{GitoriousConfig['scheme']}://whatever.#{@host}/#{@repository.project.slug}/foo.git", @repository.http_clone_url
      silence_warnings {Site::HTTP_CLONING_SUBDOMAIN = old_value}
    end

    should "has a clone url with the project name, if it is a mainline" do
      @repository.owner = groups(:team_thunderbird)
      @repository.kind = Repository::KIND_PROJECT_REPO
      assert_equal "git://#{@host}/#{@repository.project.slug}/foo.git", @repository.clone_url
    end

    should "have a clone url with the team/user, if it is not a mainline" do
      @repository.kind = Repository::KIND_TEAM_REPO
      url = "git://#{@host}/#{@repository.owner.to_param_with_prefix}/#{@repository.project.slug}/foo.git"
      assert_equal url, @repository.clone_url

      @repository.kind = Repository::KIND_USER_REPO
      @repository.owner = users(:johan)
      url = "git://#{@host}/#{users(:johan).to_param_with_prefix}/#{@repository.project.slug}/foo.git"
      assert_equal url, @repository.clone_url
    end

    should "has a push url with the project name, if it is a mainline" do
      @repository.owner = groups(:team_thunderbird)
      @repository.kind = Repository::KIND_PROJECT_REPO
      assert_equal "#{@host_with_user}:#{@repository.project.slug}/foo.git", @repository.push_url
    end

    should "have a push url with the team/user, if it is not a mainline" do
      @repository.owner = groups(:team_thunderbird)
      @repository.kind = Repository::KIND_TEAM_REPO
      url = "#{@host_with_user}:#{groups(:team_thunderbird).to_param_with_prefix}/#{@repository.project.slug}/foo.git"
      assert_equal url, @repository.push_url

      @repository.kind = Repository::KIND_USER_REPO
      @repository.owner = users(:johan)
      url = "#{@host_with_user}:#{users(:johan).to_param_with_prefix}/#{@repository.project.slug}/foo.git"
      assert_equal url, @repository.push_url
    end

    should "has a http clone url with the project name, if it is a mainline" do
      @repository.owner = groups(:team_thunderbird)
      @repository.kind = Repository::KIND_PROJECT_REPO
      assert_equal "#{GitoriousConfig['scheme']}://git.#{@host}/#{@repository.project.slug}/foo.git", @repository.http_clone_url
    end

    should "have a http clone url with the team/user, if it is not a mainline" do
      @repository.owner = groups(:team_thunderbird)
      @repository.kind = Repository::KIND_TEAM_REPO
      url = "#{GitoriousConfig['scheme']}://git.#{@host}/#{groups(:team_thunderbird).to_param_with_prefix}/#{@repository.project.slug}/foo.git"
      assert_equal url, @repository.http_clone_url

      @repository.owner = users(:johan)
      @repository.kind = Repository::KIND_USER_REPO
      url = "#{GitoriousConfig['scheme']}://git.#{@host}/#{users(:johan).to_param_with_prefix}/#{@repository.project.slug}/foo.git"
      assert_equal url, @repository.http_clone_url
    end

    should "has a full repository_path" do
      expected_dir = File.expand_path(File.join(RepositoryRoot.default_base_path,
        "#{@repository.full_hashed_path}.git"))
      assert_equal expected_dir, @repository.full_repository_path
    end

    should "always display SSH URLs when so instructed" do
      old_value = GitoriousConfig["always_display_ssh_url"]
      GitoriousConfig["always_display_ssh_url"] = true
      assert @repository.display_ssh_url?(users(:moe))
      GitoriousConfig["always_display_ssh_url"] = old_value
    end
  end

  should "inits the git repository" do
    path = @repository.full_repository_path
    Repository.git_backend.expects(:create).with(path).returns(true)
    Repository.create_git_repository(@repository.real_gitdir)

    assert File.exist?(path), "File.exist?(path) should be true"

    Dir.chdir(path) do
      hooks = File.join(path, "hooks")
      assert File.exist?(hooks), "File.exist?(hooks) should be true"
      assert File.symlink?(hooks), "File.symlink?(hooks) should be true"
      assert File.symlink?(File.expand_path(File.readlink(hooks))), "File.symlink?(File.expand_path(File.readlink(hooks))) should be true"
    end
  end

  should "clones a git repository" do
    source = repositories(:johans)
    target = @repository
    target_path = @repository.full_repository_path

    git_backend = mock("Git backend")
    Repository.expects(:git_backend).returns(git_backend)
    git_backend.expects(:clone).with(target.full_repository_path,
      source.full_repository_path).returns(true)
    Repository.expects(:create_hooks).returns(true)

    assert Repository.clone_git_repository(target.real_gitdir, source.real_gitdir)
  end

  should "not create hooks if the :skip_hooks option is set to true" do
    source = repositories(:johans)
    target = @repository
    target_path = @repository.full_repository_path

    git_backend = mock("Git backend")
    Repository.expects(:git_backend).returns(git_backend)
    git_backend.expects(:clone).with(target.full_repository_path,
      source.full_repository_path).returns(true)
    Repository.expects(:create_hooks).never

    Repository.clone_git_repository(target.real_gitdir, source.real_gitdir, :skip_hooks => true)
  end

  should "create the hooks" do
    hooks = "/path/to/hooks"
    path = "/path/to/repository"
    base_path = "#{Rails.root}/data/hooks"

    File.expects(:join).in_sequence.with(RepositoryRoot.default_base_path, ".hooks").returns(hooks)

    Dir.expects(:chdir).in_sequence.with(path).yields(nil)

    File.expects(:symlink?).in_sequence.with(hooks).returns(false)
    File.expects(:exist?).in_sequence.with(hooks).returns(false)
    FileUtils.expects(:ln_s).in_sequence.with(base_path, hooks)

    local_hooks = "/path/to/local/hooks"
    File.expects(:join).in_sequence.with(path, "hooks").returns(local_hooks)
    File.expects(:exist?).in_sequence.with(local_hooks).returns(true)

    Repository.create_hooks(path)
  end

  should "deletes a repository" do
    Repository.git_backend.expects(:delete!).with(@repository.full_repository_path).returns(true)
    Repository.delete_git_repository(@repository.real_gitdir)
  end

  should "knows if has commits" do
    @repository.stubs(:new_record?).returns(false)
    @repository.stubs(:ready?).returns(true)
    git_mock = mock("Grit::Git")
    @repository.stubs(:git).returns(git_mock)
    head = mock("head")
    head.stubs(:name).returns("master")
    @repository.git.expects(:heads).returns([head])
    assert @repository.has_commits?, "@repository.has_commits? should be true"
  end

  should "knows if has commits, unless its a new record" do
    @repository.stubs(:new_record?).returns(false)
    assert !@repository.has_commits?, "@repository.has_commits? should be false"
  end

  should "knows if has commits, unless its not ready" do
    @repository.stubs(:ready?).returns(false)
    assert !@repository.has_commits?, "@repository.has_commits? should be false"
  end

  should " build a new repository by cloning another one" do
    repos = Repository.new_by_cloning(@repository)
    assert_equal @repository, repos.parent
    assert_equal @repository.project, repos.project
    assert repos.new_record?, "new_record? should be true"
  end

  should "inherit merge request inclusion from its parent" do
    @repository.update_attribute(:merge_requests_enabled, true)
    clone = Repository.new_by_cloning(@repository)
    assert clone.merge_requests_enabled?
    @repository.update_attribute(:merge_requests_enabled, false)
    clone = Repository.new_by_cloning(@repository)
    assert !clone.merge_requests_enabled?
  end

  should "suggests a decent name for a cloned repository bsed on username" do
    repos = Repository.new_by_cloning(@repository, username="johan")
    assert_equal "johans-foo", repos.name
    repos = Repository.new_by_cloning(@repository, username=nil)
    assert_equal nil, repos.name
  end

  should "has it is name as its to_param value" do
    @repository.save
    assert_equal @repository.name, @repository.to_param
  end

  should "finds a repository by name or raises" do
    assert_equal repositories(:johans), Repository.find_by_name!(repositories(:johans).name)
    assert_raises(ActiveRecord::RecordNotFound) do
      Repository.find_by_name!("asdasdasd")
    end
  end

  context "find_by_path" do
    should "finds a repository by its path" do
      repo = repositories(:johans)
      path = File.join(RepositoryRoot.default_base_path,
                        projects(:johans).slug, "#{repo.name}.git")
      assert_equal repo, Repository.find_by_path(path)
    end

    should_eventually "finds a repository by its path, regardless of repository kind" do
      repo = projects(:johans).wiki_repository
      path = File.join(RepositoryRoot.default_base_path.chomp("/"),
                        projects(:johans).slug, "#{repo.name}.git")
      assert_equal repo, Repository.find_by_path(path)
    end

    should "finds a group repository by its path" do
      repo = repositories(:johans)
      repo.owner = groups(:team_thunderbird)
      repo.kind = Repository::KIND_TEAM_REPO
      repo.save!
      path = File.join(RepositoryRoot.default_base_path, repo.gitdir)
      assert_equal repo, Repository.find_by_path(path)
    end

    should "finds a user repository by its path" do
      repo = repositories(:johans)
      repo.owner = users(:johan)
      repo.kind = Repository::KIND_USER_REPO
      repo.save!
      path = File.join(RepositoryRoot.default_base_path, repo.gitdir)
      assert_equal repo, Repository.find_by_path(path)
    end

    should "scope the find by project id" do
      repo = repositories(:johans)
      repo.owner = groups(:team_thunderbird)
      repo.kind = Repository::KIND_TEAM_REPO
      repo.save!
      same_name_repo = new_repos(:name => repo.name)
      same_name_repo
      same_name_repo.project = projects(:moes)
      same_name_repo.owner = groups(:team_thunderbird)
      same_name_repo.kind = Repository::KIND_TEAM_REPO
      same_name_repo.save!
      path = File.join(RepositoryRoot.default_base_path, same_name_repo.gitdir)
      assert_equal same_name_repo, Repository.find_by_path(path)
    end
  end

  context "#to_xml" do
    should "xmlilizes git paths as well" do
      assert @repository.to_xml.include?("<clone-url>")
      assert @repository.to_xml.include?("<push-url>")
    end

    should "include a description of the kind" do
      assert_match(/<kind>mainline<\/kind>/, @repository.to_xml)
      @repository.kind = Repository::KIND_TEAM_REPO
      assert_match(/<kind>team<\/kind>/, @repository.to_xml)
    end

    should "include the project name" do
      assert_match(/<project>#{@repository.project.slug}<\/project>/, @repository.to_xml)
    end

    should "include the owner" do
      assert_match(/<owner kind="User">johan<\/owner>/, @repository.to_xml)
    end
  end

  context "can_push?" do
    should "knows if a user can write to self" do
      @repository.owner = users(:johan)
      @repository.save!
      @repository.reload
      assert can_push?(users(:johan), @repository)
      assert !can_push?(users(:mike), @repository)

      @repository.change_owner_to!(groups(:team_thunderbird))
      @repository.save!
      assert !can_push?(users(:johan), @repository)

      @repository.owner.add_member(users(:moe), Role.member)
      @repository.committerships.reload
      assert can_push?(users(:moe), @repository)
    end

    context "a wiki repository" do
      setup do
        @repository.kind = Repository::KIND_WIKI
      end

      should "be writable by everyone" do
        @repository.wiki_permissions = Repository::WIKI_WRITABLE_EVERYONE
        [:johan, :mike, :moe].each do |login|
          assert can_push?(users(login), @repository), "not writable_by #{login}"
        end
      end

      should "only be writable by project members" do
        @repository.wiki_permissions = Repository::WIKI_WRITABLE_PROJECT_MEMBERS
        assert @repository.project.member?(users(:johan))
        assert can_push?(users(:johan), @repository)

        assert !@repository.project.member?(users(:moe))
        assert !can_push?(users(:moe), @repository)
      end
    end
  end

  should "publishe a message on create and update" do
    @repository.save!

    assert_published("/queue/GitoriousRepositoryCreation", {
                       "command" => "create_git_repository",
                       "target_id" => @repository.id,
                       "arguments" => [@repository.real_gitdir]
                     })
  end

  should "publishe a message on clone" do
    @repository.parent = repositories(:johans)
    @repository.save!

    assert_published("/queue/GitoriousRepositoryCreation", {
                       "command" => "clone_git_repository",
                       "target_id" => @repository.id,
                       "arguments" => [@repository.real_gitdir,
                                       @repository.parent.real_gitdir]
                     })
  end

  should "create a notification on destroy" do
    @repository.save!
    @repository.destroy

    assert_published("/queue/GitoriousRepositoryDeletion", {
                       "command" => "delete_git_repository",
                       "arguments" => [@repository.real_gitdir]
                     })
  end

  should "has one recent commit" do
    @repository.save!
    repos_mock = mock("Git mock")
    commit_mock = stub_everything("Git::Commit mock")
    repos_mock.expects(:commits).with("master", 1).returns([commit_mock])
    @repository.stubs(:git).returns(repos_mock)
    @repository.stubs(:has_commits?).returns(true)
    heads_stub = mock("head")
    heads_stub.stubs(:name).returns("master")
    @repository.stubs(:head_candidate).returns(heads_stub)
    assert_equal commit_mock, @repository.last_commit
  end

  should "has one recent commit within a given ref" do
    @repository.save!
    repos_mock = mock("Git mock")
    commit_mock = stub_everything("Git::Commit mock")
    repos_mock.expects(:commits).with("foo", 1).returns([commit_mock])
    @repository.stubs(:git).returns(repos_mock)
    @repository.stubs(:has_commits?).returns(true)
    @repository.expects(:head_candidate).never
    assert_equal commit_mock, @repository.last_commit("foo")
  end

  context "deletion" do
    setup do
      @repository.kind = Repository::KIND_PROJECT_REPO
      @repository.project.repositories << new_repos(:name => "another")
      @repository.save!
      @repository.committerships.create!({
        :committer => users(:moe),
        :permissions => (Committership::CAN_REVIEW | Committership::CAN_COMMIT)
      })
    end

    should "be deletable by admins" do
      assert admin?(users(:johan), @repository)
      assert !admin?(users(:moe), @repository)

      assert can_delete?(users(:johan), @repository)
      assert !can_delete?(users(:moe), @repository)
    end

    should "always be deletable if admin and non-project repo" do
      @repository.kind = Repository::KIND_TEAM_REPO
      assert can_delete?(users(:johan), @repository)
      assert !can_delete?(users(:moe), @repository)
    end

    should "also be deletable by users with admin privs" do
      @repository.kind = Repository::KIND_TEAM_REPO
      cs = @repository.committerships.create_with_permissions!({
          :committer => users(:mike)
        }, Committership::CAN_ADMIN)
      assert can_delete?(users(:johan), @repository)
      assert can_delete?(users(:mike), @repository)
    end
  end

  should "have a git method that accesses the repository" do
    # FIXME: meh for stubbing internals, need to refactor that part in Grit
    File.expects(:exist?).at_least(1).with("#{@repository.full_repository_path}/.git").returns(false)
    File.expects(:exist?).at_least(1).with(@repository.full_repository_path).returns(true)
    assert_instance_of Grit::Repo, @repository.git
    assert_equal @repository.full_repository_path, @repository.git.path
  end

  should "have a head_candidate" do
    head_stub = mock("head")
    head_stub.stubs(:name).returns("master")
    git = mock("git backend")
    @repository.stubs(:git).returns(git)
    git.expects(:head).returns(head_stub)
    @repository.expects(:has_commits?).returns(true)

    assert_equal head_stub, @repository.head_candidate
  end

  should "have a head_candidate, unless it does not have commits" do
    @repository.expects(:has_commits?).returns(false)
    assert_equal nil, @repository.head_candidate
  end

  should "has paginated_commits" do
    git = mock("git")
    commits = [mock("commit"), mock("commit")]
    @repository.expects(:git).times(2).returns(git)
    git.expects(:commit_count).returns(120)
    git.expects(:commits).with("foo", 30, 30).returns(commits)
    commits = @repository.paginated_commits("foo", 2, 30)
    assert_instance_of WillPaginate::Collection, commits
  end

  should "has a count_commits_from_last_week_by_user of 0 if no commits" do
    @repository.expects(:has_commits?).returns(false)
    assert_equal 0, @repository.count_commits_from_last_week_by_user(users(:johan))
  end

  should "returns a set of users from a list of commits" do
    commits = []
    users(:johan, :moe).map do |u|
      committer = OpenStruct.new(:email => u.email)
      commits << OpenStruct.new(:committer => committer, :author => committer)
    end
    users = Repository.users_by_commits(commits)
    assert_equal users(:johan, :moe).map(&:email).sort, users.keys.sort
    assert_equal users(:johan, :moe).map(&:login).sort, users.values.map(&:login).sort
  end

  should "know if it is a normal project repository" do
    assert @repository.project_repo?, "@repository.project_repo? should be true"
  end

  should "know if it is a wiki repo" do
    @repository.kind = Repository::KIND_WIKI
    assert @repository.wiki?, "@repository.wiki? should be true"
  end

  should "has a parent, which is the owner" do
    @repository.kind = Repository::KIND_TEAM_REPO
    @repository.owner = groups(:team_thunderbird)
    assert_equal groups(:team_thunderbird), @repository.breadcrumb_parent

    @repository.kind = Repository::KIND_USER_REPO
    @repository.owner = users(:johan)
    assert_equal users(:johan), @repository.breadcrumb_parent
  end

  should "has a parent, which is the project for mainlines" do
    @repository.kind = Repository::KIND_PROJECT_REPO
    @repository.owner = groups(:team_thunderbird)
    assert_equal projects(:johans), @repository.breadcrumb_parent

    @repository.owner = users(:johan)
    assert_equal projects(:johans), @repository.breadcrumb_parent
  end

  should " return its name as title" do
    assert_equal @repository.title, @repository.name
  end

  should "return the project title as owner_title if it is a mainline" do
    @repository.kind = Repository::KIND_PROJECT_REPO
    assert_equal @repository.project.title, @repository.owner_title
  end

  should "return the owner title as owner_title if it is not a mainline" do
    @repository.kind = Repository::KIND_TEAM_REPO
    assert_equal @repository.owner.title, @repository.owner_title
  end

  should "returns a list of committers depending on owner type" do
    repo = repositories(:johans2)
    repo.committerships.each(&:delete)
    repo.reload
    assert !committers(repo).include?(users(:moe))

    repo.committerships.create_with_permissions!({
        :committer => users(:johan)
      }, Committership::CAN_COMMIT)
    assert_equal [users(:johan).login], committers(repo).map(&:login)

    repo.committerships.create_with_permissions!({
        :committer => groups(:team_thunderbird)
      }, Committership::CAN_COMMIT)
    exp_users = groups(:team_thunderbird).members.unshift(users(:johan))
    assert_equal exp_users.map(&:login), committers(repo).map(&:login)

    groups(:team_thunderbird).add_member(users(:moe), Role.admin)
    repo.reload
    assert committers(repo).include?(users(:moe))
  end


  should "know you can request merges from it"  do
    repo = repositories(:johans2)
    assert !repo.mainline?
    assert committer?(users(:mike), repo)
    assert can_request_merge?(users(:mike), repo)

    repo.kind = Repository::KIND_PROJECT_REPO
    assert repo.mainline?
    assert !can_request_merge?(users(:mike), repo), "mainlines should not request merges"
  end

  should "use a sharded hashed path if enable_repository_dir_sharding is toggled" do
    GitoriousConfig["enable_repository_dir_sharding"] = true
    repository = new_repos
    assert repository.new_record?, "repository.new_record? should be true"
    repository.save!
    assert_not_nil repository.hashed_path
    assert_equal 3, repository.hashed_path.split("/").length
    assert_match(/[a-z0-9\/]{42}/, repository.hashed_path)
    GitoriousConfig["enable_repository_dir_sharding"] = false
  end

  should "use repo name for path by default, not sharded hashed paths" do
    GitoriousConfig["enable_repository_dir_sharding"] = false
    repository = new_repos
    FileUtils.mkdir_p(repository.full_repository_path, :mode => 0755)
    repository.save!
    assert_equal "#{repository.project.slug}/#{repository.name}", repository.hashed_path
  end

  should "create the initial committership on create for owner" do
    group_repo = new_repos(:owner => groups(:team_thunderbird))
    assert_difference("Committership.count") do
      group_repo.save!
      assert_equal 1, group_repo.committerships.count
      assert_equal groups(:team_thunderbird), group_repo.committerships.first.committer
    end

    user_repo = new_repos(:owner => users(:johan), :name => "foo2")
    assert_difference("Committership.count") do
      user_repo.save!
      assert_equal 1, user_repo.committerships.count
      cs = user_repo.committerships.first
      assert_equal users(:johan), cs.committer
      [:reviewer?, :committer?, :admin?].each do |m|
        assert cs.send(m), "should have #{m} permissions"
      end
    end
  end

  should "know the full hashed path" do
    assert_equal @repository.hashed_path, @repository.full_hashed_path
  end

  should "allow changing ownership from a user to a group" do
    repo = repositories(:johans)
    repo.change_owner_to!(groups(:team_thunderbird))
    assert_equal groups(:team_thunderbird), repo.owner
    repo.change_owner_to!(users(:johan))
    assert_equal groups(:team_thunderbird), repo.owner
  end

  should "not change kind when it is a project repo and changing owner" do
    repo = repositories(:johans)
    repo.change_owner_to!(groups(:team_thunderbird))
    assert_equal groups(:team_thunderbird), repo.owner
    assert_equal Repository::KIND_PROJECT_REPO, repo.kind
  end

  should "change kind when changing owner" do
    repo = repositories(:johans)
    repo.update_attribute(:kind, Repository::KIND_USER_REPO)
    assert repo.user_repo?
    repo.change_owner_to!(groups(:team_thunderbird))
    assert_equal groups(:team_thunderbird), repo.owner
    assert repo.team_repo?
  end

  should "changing ownership adds the new owner to the committerships" do
    repo = repositories(:johans)
    old_committer = repo.owner
    repo.change_owner_to!(groups(:team_thunderbird))
    assert !committers(repo).include?(old_committer)
    assert committers(repo).include?(groups(:team_thunderbird).members.first)
    [:reviewer?, :committer?, :admin?].each do |m|
      assert repo.committerships.last.send(m), "cannot #{m}"
    end
  end

  should "upgrade the permissions for the new owner when it already has access" do
    new_owner = groups(:team_thunderbird)
    repo = repositories(:johans)
    committership = repo.committerships.create_with_permissions!({:committer => new_owner}, Committership::CAN_COMMIT)

    repo.change_owner_to!(new_owner)
    assert committership.reload.admin?
  end

  should "downcases the name before validation" do
    repo = new_repos(:name => "FOOBAR")
    repo.save!
    assert_equal "foobar", repo.reload.name
  end

  should "have a project_or_owner" do
    repo = repositories(:johans)
    assert repo.project_repo?
    assert_equal repo.project, repo.project_or_owner

    repo.kind = Repository::KIND_TEAM_REPO
    repo.owner = groups(:team_thunderbird)
    assert_equal repo.owner, repo.project_or_owner

    repo.kind = Repository::KIND_TEAM_REPO
    repo.owner = groups(:team_thunderbird)
    assert_equal repo.owner, repo.project_or_owner
  end

  context "participant groups" do
    setup do
      @repo = repositories(:moes)
    end

    should "includes the groups' members in #committers" do
      assert committers(@repo).include?(groups(:team_thunderbird).members.first)
    end

    should "only include unique users in #committers" do
      groups(:team_thunderbird).add_member(users(:moe), Role.member)
      assert_equal 1, committers(@repo).select{|u| u == users(:moe)}.size
    end

    should "not include committerships without a commit permission bit" do
      assert_equal 1, @repo.committerships.count
      cs = @repo.committerships.first
      cs.build_permissions(:review)
      cs.save!
      assert_equal [], committers(@repo).map(&:login)
    end

    should "return a list of reviewers" do
      assert !reviewers(@repo).map(&:login).include?(users(:moe).login)
      @repo.committerships.create_with_permissions!({
          :committer => users(:moe)
        }, Committership::CAN_REVIEW)
      assert reviewers(@repo).map(&:login).include?(users(:moe).login)
    end

    context "permission helpers" do
      setup do
        @cs = @repo.committerships.first
        @cs.permissions = 0
        @cs.save!
      end

      should "know if a user is a committer" do
        assert !committer?(@cs.committer, @repo)
        @cs.build_permissions(:commit); @cs.save
        assert !committer?(:false, @repo)
        assert !committer?(@cs.committer, @repo)
      end

      should "know if a user is a reviewer" do
        assert !reviewer?(@cs.committer, @repo)
        @cs.build_permissions(:review); @cs.save
        assert !reviewer?(:false, @repo)
        assert !reviewer?(@cs.committer, @repo)
      end

      should "know if a user is a admin" do
        assert !admin?(@cs.committer, @repo)
        @cs.build_permissions(:commit, :admin); @cs.save
        assert !admin?(:false, @repo)
        assert !admin?(@cs.committer, @repo)
      end
    end
  end

  context "owners as User or Group" do
    setup do
      @repo = repositories(:moes)
    end

    should "return a list of the users who are admin for the repository if owned_by_group?" do
      @repo.change_owner_to!(groups(:a_team))
      assert_equal([users(:johan)], @repo.owners)
    end

    should "not throw an error if transferring ownership to a group if the group is already a committer" do
      @repo.change_owner_to!(groups(:team_thunderbird))
      assert_equal([users(:mike)], @repo.owners)
    end

    should "return the owner if owned by user" do
      @repo.change_owner_to!(users(:moe))
      assert_equal([users(:moe)], @repo.owners)
    end
  end

  should "create an event on create if it is a project repo" do
    repo = new_repos
    repo.kind = Repository::KIND_PROJECT_REPO
    assert_difference("repo.project.events.count") do
      repo.save!
    end
    assert_equal repo, Event.last.target
    assert_equal Action::ADD_PROJECT_REPOSITORY, Event.last.action
  end

  context "find_by_name_in_project" do
    should "find with a project" do
      Repository.expects(:find_by_name_and_project_id!).with(repositories(:johans).name, projects(:johans).id).once
      Repository.find_by_name_in_project!(repositories(:johans).name, projects(:johans))
    end

    should "find without a project" do
      Repository.expects(:find_by_name!).with(repositories(:johans).name).once
      Repository.find_by_name_in_project!(repositories(:johans).name)
    end
  end

  context "Signoff of merge requests" do
    setup do
      @project = projects(:johans)
      @mainline_repository = repositories(:johans)
      @other_repository = repositories(:johans2)
    end

    should "know that the mainline repository requires signoff of merge requests" do
      assert @mainline_repository.mainline?
      assert @mainline_repository.requires_signoff_on_merge_requests?
    end

    should "not require signoff of merge requests in other repositories" do
      assert !@other_repository.mainline?
      assert !@other_repository.requires_signoff_on_merge_requests?
    end
  end

  context "Merge request status tags" do
    setup {@repo = repositories(:johans)}

    should "have a list of used status tags" do
      @repo.merge_requests.last.update_attribute(:status_tag, "worksforme")
      assert_equal %w[open worksforme], @repo.merge_request_status_tags
    end
  end

  context "Thottling" do
    setup{ Repository.destroy_all }

    should "throttle on create" do
      assert_nothing_raised do
        5.times{|i| new_repos(:name => "wifebeater#{i}").save! }
      end

      assert_no_difference("Repository.count") do
        assert_raises(RecordThrottling::LimitReachedError) do
          new_repos(:name => "wtf-are-you-doing-bro").save!
        end
      end
    end
  end

  context "Logging updates" do
    setup {@repository = repositories(:johans)}

    should "generate events for each value that is changed" do
      assert_incremented_by(@repository.events, :size, 1) do
        @repository.log_changes_with_user(users(:johan)) do
          @repository.replace_value(:name, "new_name")
        end
        assert @repository.save
      end
      assert_equal "new_name", @repository.reload.name
    end

    should "not generate events when blank values are provided" do
      assert_incremented_by(@repository.events, :size, 0) do
        @repository.log_changes_with_user(users(:johan)) do
          @repository.replace_value(:name, "")
        end
      end
    end

    should "allow blank updates if we say it is ok" do
      @repository.update_attribute(:description, "asdf")
      @repository.log_changes_with_user(users(:johan)) do
        @repository.replace_value(:description, "", true)
      end
      @repository.save!
      assert @repository.reload.description.blank?, "desc: #{@repository.description.inspect}"
    end

    should "not generate events when invalid values are provided" do
      assert_incremented_by(@repository.events, :size, 0) do
        @repository.log_changes_with_user(users(:johan)) do
          @repository.replace_value(:name, "Some illegal value")
        end
      end
    end

    should "not generate events when a value is unchanged" do
      assert_incremented_by(@repository.events, :size, 0) do
        @repository.log_changes_with_user(users(:johan)) do
          @repository.replace_value(:name, @repository.name)
        end
      end
    end
  end

  context "changing the HEAD" do
    setup do
      @grit = Grit::Repo.new(grit_test_repo("dot_git"), :is_bare => true)
      @repository.stubs(:git).returns(@grit)
    end

    should "change the head" do
      assert the_head = @grit.get_head("test/master")
      @grit.expects(:update_head).with(the_head).returns(true)
      @repository.head = the_head.name
    end

    should "not change the head if given a nonexistant ref" do
      @grit.expects(:update_head).never
      @repository.head = "non-existant"
      @repository.head = nil
      @repository.head = ""
    end

    should "change the head, even if the current head is nil" do
      assert the_head = @grit.get_head("test/master")
      @grit.expects(:head).returns(nil)
      @grit.expects(:update_head).with(the_head).returns(true)
      @repository.head = the_head.name
    end
  end

  context "Merge request repositories" do
    setup do
      @project = Factory.create(:user_project)
      @main_repo = Factory.create(:repository, :project => @project, :owner => @project.owner, :user => @project.user)
    end

    should "initially not have a merge request repository" do
      assert !@main_repo.has_tracking_repository?
    end

    should "generate a tracking repository" do
      @merge_repo = @main_repo.create_tracking_repository
      assert @main_repo.project_repo?
      assert @merge_repo.tracking_repo?
      assert_equal @main_repo, @merge_repo.parent
      assert_equal @main_repo.owner, @merge_repo.owner
      assert_equal @main_repo.user, @merge_repo.user
      assert @main_repo.has_tracking_repository?
      assert_equal @merge_repo, @main_repo.tracking_repository
    end

    should "not post a repository creation message for merge request repositories" do
      @merge_repo = @main_repo.build_tracking_repository
      @merge_repo.expects(:publish).never
      assert @merge_repo.save
    end
  end

  context "Merge requests enabling" do
    setup do
      @repository = Repository.new
    end

    should "by default allow merge requests" do
      assert @repository.merge_requests_enabled?
    end
  end

  context "garbage collection" do
    setup do
      @repository = repositories(:johans)
      @now = Time.now
      Time.stubs(:now).returns(@now)
      @repository.stubs(:git).returns(stub())
      @repository.git.stubs(:git).returns(stub())
      @repository.git.git.expects(:gc).returns(true)
    end

    should "have a gc! method that updates last_gc_at" do
      assert_nil @repository.last_gc_at
      assert @repository.gc!
      assert_not_nil @repository.last_gc_at
      assert_equal @now, @repository.last_gc_at
    end

    should "set push_count_since_gc to 0 when doing gc" do
      @repository.push_count_since_gc = 10
      @repository.gc!
      assert_equal 0, @repository.push_count_since_gc
    end
  end

  context "Fresh repositories" do
    setup do
      Repository.destroy_all
      @me = Factory.create(:user, :login => "johnnie")
      @project = Factory.create(:project, :user => @me,
        :owner => @me)
      @repo = Factory.create(:repository, :project => @project,
        :owner => @project, :user => @me)
      @users = %w(bill steve jack nellie).map { | login |
        Factory.create(:user, :login => login)
      }
      @user_repos = @users.map do |u|
        new_repo = Repository.new_by_cloning(@repo)
        new_repo.name = "#{u.login}s-clone"
        new_repo.user = u
        new_repo.owner = u
        new_repo.kind = Repository::KIND_USER_REPO
        new_repo.last_pushed_at = 1.hour.ago
        assert new_repo.save
        new_repo
      end
    end

    should "include repositories recently pushed to" do
      assert @project.repositories.reload.by_users.fresh(2).include?(@user_repos.first)
    end

    should "not include repositories last pushed to in the middle ages" do
      older_repo = @user_repos.pop
      older_repo.last_pushed_at = 500.years.ago
      older_repo.save
      assert !@project.repositories.by_users.fresh(2).include?(older_repo)
    end

  end

  context "Searching clones" do
    setup do
      @repo = repositories(:johans)
      @clone = repositories(:johans2)
    end

    should "find clones matching an owning group's name" do
      assert @repo.clones.include?(@clone)
      assert @repo.search_clones("sproject").include?(@clone)
    end

    context "by user name" do
      setup do
        @repo = repositories(:moes)
        @clone = repositories(:johans_moe_clone)
        users(:johan).update_attribute(:login, "rohan")
        @clone.update_attribute(:name, "rohans-clone-of-moes")
      end

      should "match users with a matching name" do
        assert_includes(@repo.search_clones("rohan"), @clone)
      end

      should "not match user with diverging name" do
        assert_not_includes(@repo.search_clones("johan"), @clone)
      end
    end

    context "by group name" do
      setup do
        @repo = repositories(:johans)
        @clone = repositories(:johans2)
      end

      should "match groups with a matching name" do
        assert_includes(@repo.search_clones("thunderbird"), @clone)
      end

      should "not match groups with diverging name" do
        assert_not_includes(@repo.search_clones("A-team"), @clone)
      end
    end

    context "by repo name and description" do
      setup do
        @repo = repositories(:johans)
        @clone = repositories(:johans2)
      end

      should "match repos with a matching name" do
        assert_includes(@repo.search_clones("projectrepos"), @clone)
      end

      should "not match repos with a different parent" do
        assert_not_includes(@repo.search_clones("projectrepos"), repositories(:moes))
      end
    end

  end

  context "Sequences" do
    setup do
      @repository = repositories(:johans)
    end

    should "calculate the highest existing sequence number" do
      assert_equal(@repository.merge_requests.max_by(&:sequence_number).sequence_number,
        @repository.calculate_highest_merge_request_sequence_number)
    end

    should "calculate the number of merge requests" do
      assert_equal(3, @repository.merge_request_count)
    end

    should "be the number of merge requests for a given repo" do
      assert_equal 3, @repository.merge_requests.size
      assert_equal 4, @repository.next_merge_request_sequence_number
    end

    # 3 merge requests, update one to have seq 4
    should "handle taken sequence numbers gracefully" do
      last_merge_request = @repository.merge_requests.last
      last_merge_request.update_attribute(:sequence_number, 4)
      @repository.expects(:calculate_highest_merge_request_sequence_number).returns(99)
      assert_equal(100,
        @repository.next_merge_request_sequence_number)
    end
  end

  context "default favoriting" do
    should "add the owner as a watcher when creating a clone" do
      user = users(:mike)
      repo = Repository.new_by_cloning(repositories(:johans), "mike")
      repo.user = repo.owner = user
      assert_difference("user.favorites.reload.count") do
        repo.save!
      end
      assert repo.reload.watched_by?(user)
    end

    should "not add as watcher if it is an internal repository" do
      repo = new_repos(:user => users(:moe))
      repo.kind = Repository::KIND_TRACKING_REPO
      assert_no_difference("users(:moe).favorites.count") do
        repo.save!
      end
    end
  end

  context "Calculation of disk usage" do
    setup do
      @repository = repositories(:johans)
      @bytes = 90129
    end

    should "save the bytes used" do
      @repository.expects(:calculate_disk_usage).returns(@bytes)
      @repository.update_disk_usage
      assert_equal @bytes, @repository.disk_usage
    end
  end

  context "Pushing" do
    setup do
      @repository = repositories(:johans)
    end

    should "update last_pushed_at" do
      @repository.last_pushed_at = 1.hour.ago.utc
      @repository.stubs(:update_disk_usage)
      @repository.register_push
      assert @repository.last_pushed_at > 1.hour.ago.utc
    end

    should "increment the number of pushes" do
      @repository.push_count_since_gc = 2
      @repository.stubs(:update_disk_usage)
      @repository.register_push
      assert_equal 3, @repository.push_count_since_gc
    end

    should "call update_disk_usage when registering a push" do
      @repository.expects(:update_disk_usage)
      @repository.register_push
    end
  end

  context "Database authorization" do
    context "with private repositories enabled" do
      setup do
        GitoriousConfig["enable_private_repositories"] = true
        @repository = repositories(:johans)
      end

      should "mark repository as private" do
        @repository.make_private
        assert @repository.private?
      end

      should "mark repository as private if project is private" do
        @repository.project.make_private
        assert @repository.private?
      end

      should "allow anonymous user to view public repository" do
        repository = Repository.new(:name => "My repository")
        assert can_read?(nil, repository)
      end

      should "allow owner to view private repository" do
        @repository.owner = users(:johan)
        @repository.add_member(users(:johan))
        assert can_read?(users(:johan), @repository)
      end

      should "disallow anonymous user to view private repository" do
        @repository.add_member(users(:johan))
        assert !can_read?(nil, @repository)
      end

      should "disallow repository member if not also project member" do
        @repository.add_member(users(:mike))
        @repository.project.make_private

        assert !can_read?(nil, @repository)
      end

      should "allow member to view private repository" do
        @repository.owner = users(:johan)
        @repository.add_member(users(:mike))
        assert can_read?(users(:mike), @repository)
      end

      should "allow member to view private repository via group membership" do
        @repository.owner = users(:johan)
        @repository.add_member(groups(:team_thunderbird))
        assert can_read?(users(:mike), @repository)
      end

      should "display the git URL for public repositories" do
        assert @repository.git_cloning?
      end

      should "not display the git URL for protected repositories" do
        @repository.owner = users(:johan)
        @repository.add_member(users(:mike))
        assert !@repository.git_cloning?
      end
    end

    context "with private repositories disabled" do
      setup do
        GitoriousConfig["enable_private_repositories"] = false
        @repository = repositories(:johans)
      end

      should "allow anonymous user to view 'private' repository" do
        @repository.add_member(users(:johan))
        assert can_read?(nil, @repository)
      end
    end

    context "making repositories private" do
      setup do
        @user = users(:johan)
        @repository = repositories(:johans)
        GitoriousConfig["enable_private_repositories"] = true
      end

      should "add owner as member" do
        @repository.make_private
        assert !can_read?(users(:mike), @repository)
      end
    end
  end

  context "repository memberships" do
    should "silently ignore duplicates" do
      repository = repositories(:johans)
      repository.add_member(users(:mike))
      repository.add_member(users(:mike))

      assert repository.member?(users(:mike))
      assert is_member?(users(:mike), repository)
      assert_equal 1, repository.content_memberships.count
    end
  end

  context "Reserved repository names" do

    should "not allow users as repository name" do
      repo = otherwise_valid_repository(:name => "users")
      assert repo.errors.on :name
    end

    should "not allow 'groups' as repository name" do
      repo = otherwise_valid_repository(:name => "groups")
      assert repo.errors.on :name
    end
  end

  context "Deletion" do
    setup {
      @repository = repositories(:johans)
    }

    should "ensure merge requests are removed first to avoid cascading validation errors" do
      mr = mock
      mr.expects(:destroy).times(2)
      @repository.stubs(:merge_requests).returns([mr])
      @repository.destroy
    end
  end

  def otherwise_valid_repository(options)
    result = new_repos(options)
    result.valid?
    result
  end
end
