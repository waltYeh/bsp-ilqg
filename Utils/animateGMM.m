function [failed, b_f] = animateGMM(b0, nSteps, motionModel, obsModel)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Animate the robot's motion from start to goal
%
% Inputs:
%   figh: Figure handle in which to draw
%   plotfn: function handle to plot cov ellipse
%   b0: initial belief
%   b_nom: nominal belief trajectory
%   u_nom: nominal controls
%   L: feedback gain
%   motionModel: robot motion model
%   obsModel: observation model
% Outputs:
% failed: 0 for no collision, 1 for collision, 2 for dynamic obstacle
% detected
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    component_stDim = motionModel.stDim;
    component_bDim = component_stDim + component_stDim^2 + 1;
    shared_uDim = 2;
    component_alone_uDim = motionModel.ctDim - shared_uDim;
    
    components_amount = length(b0)/component_bDim;
%     u_man = [u(end-shared_uDim+1);u(end)]
    
% stDim = motionModel.stDim;
comp_sel =1;
use_bad_man_speed = true;

mu = cell(components_amount,1);
sig = cell(components_amount,1);
weight = zeros(components_amount,1);
mu_save = cell(components_amount,1);
sig_save = cell(components_amount,1);
weight_save = cell(components_amount,1);
x_save = [];
x_true = [];
for i_comp=1:components_amount
    b0_comp = b0((i_comp-1)*component_bDim+1:i_comp*component_bDim);
    mu{i_comp} = b0_comp(1:component_stDim);
    for d = 1:motionModel.stDim
        sig{i_comp}(:,d) = b0_comp(d*component_stDim+1:(d+1)*component_stDim, 1);
    end
    weight(i_comp) = b0_comp(end);
    if comp_sel == i_comp
        x_true = mu{i_comp} + chol(sig{i_comp})' * randn(component_stDim,1);
        x_save = x_true;
    end
    mu_save{i_comp} = mu{i_comp};
    sig_save{i_comp} = sig{i_comp}(:);
    weight_save{i_comp} = weight(i_comp);
end

% xt = b0(1:stDim); % true state of robot
% x = b0(1:stDim); % estimated mean
% P = zeros(stDim); % covariance

% unpack covariance from belief vector
% for d = 1:stDim
%     P(:,d) = b0(d*stDim+1:(d+1)*stDim, 1);
% end

rh = []; % robot disk drawing handle

% figure(figh);
% plot(b_nom(1,:),b_nom(2,:),'b', 'LineWidth',2);

% create robot body points
global ROBOT_RADIUS
% robotDisk = ROBOT_RADIUS*[cos(linspace(0,2*pi,50));...
%     sin(linspace(0,2*pi,50))];

% trCov_vs_time(1) = trace(P);

roboTraj = [];

failed = 0;

for k = 1:nSteps

    b = zeros(component_bDim*components_amount,1); % current belief
    for i_comp=1:components_amount
        b((i_comp-1)*component_bDim+1:(i_comp-1)*component_bDim+component_stDim)=mu{i_comp};
        b((i_comp-1)*component_bDim+component_stDim+1:(i_comp-1)*component_bDim+component_stDim+component_stDim*component_stDim)=sig{i_comp};
        b((i_comp)*component_bDim)=weight(i_comp);
    end
    v_ball = [-0.3;-0.7];
    v_rest = [0.0;0.0];
    v_aid_man = [0.0;0.0];
    u = [v_ball;v_rest;v_aid_man];
%     u = u_nom(:,i) + L(:,:,i)*(b - b_nom(:,i));
    
    %% update physical part
    processNoise = motionModel.generateProcessNoise(x_true,u);
    zeroProcessNoise = zeros(4,1);
    u_for_true = [u((comp_sel-1)*components_amount + 1:comp_sel*components_amount);u(end-1:end)];
    x_next_no_spec_human_motion = motionModel.evolve(x_true,u_for_true,zeroProcessNoise);
        
    good_man_for_ball_should_output = obsModel.getObservation(x_true,'nonoise');
    good_man_speed_angle=good_man_for_ball_should_output(1:2);
    v_man = [good_man_speed_angle(1)*cos(good_man_speed_angle(2));
                good_man_speed_angle(1)*sin(good_man_speed_angle(2))];
    
    if use_bad_man_speed
        if comp_sel ==1
            v_man=[0.7;-0.2]*0.94^(k*motionModel.dt*20)*6;
            if k*motionModel.dt>1
                v_man=[0.15;0.5]*0.94^((k-nSteps/6)*motionModel.dt*20)*6;
            end
            if k*motionModel.dt>2.6
                v_man=[-0.9;0.2]*0.94^((k-nSteps/3)*motionModel.dt*20)*6;
            end
            if k*motionModel.dt>4.5
                v_man=[0.45;-1.4]*0.94^((k-nSteps/3*2)*motionModel.dt*20)*6;
            end
        elseif comp_sel ==2
            v_man = [-1.1;1.]*0.94^(k*motionModel.dt*20)*3;
        end
    end
    last_human_pos = x_true(3:4);
    x_true(1:2) = x_next_no_spec_human_motion(1:2);
    x_true(3:4) = last_human_pos + motionModel.dt*v_man;
    
        % Get observation model jacobians
    z = obsModel.getObservation(x_true,'truenoise'); % true observation
    %truely observed output is not the one modeled by ekf
    speed_man = norm(v_man);
    direction_man = atan2(v_man(2),v_man(1));
    z(1:2)=[speed_man;direction_man] + chol(obsModel.R_speed)' * randn(2,1);
    
    %% now do the machine part
    z_mu = cell(components_amount);
    z_sig = cell(components_amount);
    for i_comp = 1:components_amount
        %u = [v_ball;v_rest;v_aid_man];
        u_for_comp = [u((i_comp-1)*components_amount + 1:i_comp*components_amount);u(end-1:end)];
            % Get motion model jacobians and predict pose
    %     zeroProcessNoise = motionModel.generateProcessNoise(mu{i_comp},u_for_comp); % process noise
        zeroProcessNoise = zeros(motionModel.stDim,1);
        x_prd = motionModel.evolve(mu{i_comp},u_for_comp,zeroProcessNoise); % predict robot pose
        A = motionModel.getStateTransitionJacobian(mu{i_comp},u_for_comp,zeroProcessNoise);
        G = motionModel.getProcessNoiseJacobian(mu{i_comp},u_for_comp,zeroProcessNoise);
        Q = motionModel.getProcessNoiseCovariance(mu{i_comp},u_for_comp);
        P_prd = A*sig{i_comp}*A' + G*Q*G';

        z_prd = obsModel.getObservation(x_prd,'nonoise'); % predicted observation
        zerObsNoise = zeros(length(z),1);
        H = obsModel.getObservationJacobian(mu{i_comp},zerObsNoise);
        % M is eye
        M = obsModel.getObservationNoiseJacobian(mu{i_comp},zerObsNoise,z);
    %     R = obsModel.getObservationNoiseCovariance(x,z);
    %     R = obsModel.R_est;
        % update P
        HPH = H*P_prd*H';
    %     S = H*P_prd*H' + M*R*M';
        K = (P_prd*H')/(HPH + M*obsModel.R_est*M');
        
        weight_adjust = [weight(i_comp),weight(i_comp),1,1]';
%         K=weight_adjust.*K;
        P = (eye(motionModel.stDim) - K*H)*P_prd;
        x = x_prd + weight_adjust.*K*(z - z_prd);
        z_mu{i_comp} = z_prd;
        z_sig{i_comp} = HPH;
        mu{i_comp} = x;
        sig{i_comp} = P;
    end
    
    last_w = weight;
    for i_comp = 1 : components_amount
        weight(i_comp) = last_w(i_comp)*getLikelihood(z - z_mu{i_comp}, z_sig{i_comp} + obsModel.R_w);
    end
    sum_wk=sum(weight);
    if (sum_wk > 0)
        for i_comp = 1 : components_amount
            weight(i_comp) = weight(i_comp) ./ sum_wk;
        end
    else
        weight = last_w;
    end
    for i_comp = 1 : components_amount
        weight(i_comp) = 0.99*weight(i_comp)+0.01*0.5;
    end
    
%% now for save
    for i_comp = 1 : components_amount
        mu_save{i_comp}(:,k+1) = mu{i_comp};
        sig_save{i_comp}(:,k+1) = sig{i_comp}(:);
        weight_save{i_comp}(:,k+1) = weight(i_comp);
    end
    x_save(:,k+1) = x_true;
%     % final belief
    b_f = zeros(component_bDim*components_amount,1); % current belief
    for i_comp=1:components_amount
        b_f((i_comp-1)*component_bDim+1:(i_comp-1)*component_bDim+component_stDim)=mu{i_comp};
        b_f((i_comp-1)*component_bDim+component_stDim+1:(i_comp-1)*component_bDim+component_stDim+component_stDim*component_stDim)=sig{i_comp};
        b_f((i_comp)*component_bDim)=weight(i_comp);
    end
    
%     roboTraj(:,k) = x;
%     
%     trCov_vs_time(k+1) = trace(P);
%     
%     % if robot is in collision
%     if stateValidityChecker(x) == 0
%         figure(figh);
%         plot(roboTraj(1,:),roboTraj(2,:),'g', 'LineWidth',2);
%         drawnow;
%         warning('Robot collided :( ');
%         failed = 1;
%         return;
%     end

%     delete(rh)
%     rh = fill(mu{comp_sel}(3) + robotDisk(1,:),{comp_sel}(4) + robotDisk(2,:),'b');
%     drawResult(plotFn,b,motionModel.stDim);
%     drawnow;
    figure(1)
    plot(x_save(1,k),x_save(2,k),'.')
    hold on
    axis equal
    plot(x_save(3,k),x_save(4,k),'+')
    plot(mu_save{1}(3,k),mu_save{1}(4,k),'bo')
    plot(mu_save{1}(1,k),mu_save{1}(2,k),'bo')
    plot(mu_save{2}(1,k),mu_save{2}(2,k),'ro')
    
    pointsToPlot = drawResultGMM([mu_save{1}(:,k); sig_save{1}(:,k)], motionModel.stDim);
    plot(pointsToPlot(1,:),pointsToPlot(2,:),'b')
    pointsToPlot = drawResultGMM([mu_save{2}(:,k); sig_save{2}(:,k)], motionModel.stDim);
    plot(pointsToPlot(1,:),pointsToPlot(2,:),'r')
    figure(2)
%     time_line = 0:motionModel.dt:motionModel.dt*(nSteps);
    plot([motionModel.dt*(k-1),motionModel.dt*(k)],[weight_save{1}(k),weight_save{1}(k+1)],'-ob',[motionModel.dt*(k-1),motionModel.dt*(k)],[weight_save{2}(k),weight_save{2}(k+1)],'-ok')
    hold on
    pause(0.02);
end
% figure(1)
% plot(x_save(1,:),x_save(2,:),'.')
% hold on
% axis equal
% plot(x_save(3,:),x_save(4,:),'+')
% hold off
% figure(2)
% time_line = 0:motionModel.dt:motionModel.dt*(nSteps);
% plot(time_line,weight_save{1},'b',time_line,weight_save{2},'k')

% figure(figh);
% plot(roboTraj(1,:),roboTraj(2,:),'g', 'LineWidth',2);
% drawnow;
% failed = 0;
figure(1)
hold off
figure(2)
hold off
end