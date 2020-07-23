function [failed, b_f, x_true_final] = animateMultiagent(agents, b0, nSteps,time_past, show_mode)
% larger, less overshoot; smaller, less b-noise affects assist
P_feedback = 0.3;
% longer, clear wish, shorter, less overshoot
t_human_withdraw = 0.5;
comp_sel =1;
use_bad_man_speed = true;
EQUAL_WEIGHT_BALANCING = 1;
EQUAL_WEIGHT_TO_BALL_FEEDBACK = 2;
EQUAL_WEIGHT_TO_REST_FEEDBACK = 3;
BALL_WISH_WITHOUT_HUMAN_INPUT = 4;
BALL_WISH_WITH_HUMAN_INPUT = 5;
BALL_WISH_WITH_OPPOSITE_HUMAN_INPUT = 6;
REST_WISH_WITHOUT_HUMAN_INPUT = 7;
REST_WISH_WITH_HUMAN_INPUT = 8;
REST_WISH_WITH_OPPOSITE_HUMAN_INPUT = 9;
CHANGE_WISHES = 10;
% show_mode = EQUAL_WEIGHT_BALANCING;
switch show_mode
    case EQUAL_WEIGHT_BALANCING
        t_human_withdraw = 0.0;
    case EQUAL_WEIGHT_TO_BALL_FEEDBACK
        t_human_withdraw = 0.4;
        comp_sel =1;
    case EQUAL_WEIGHT_TO_REST_FEEDBACK
        t_human_withdraw = 0.3;
        comp_sel =2;        
    case BALL_WISH_WITHOUT_HUMAN_INPUT
        t_human_withdraw = 0.0;
    case BALL_WISH_WITH_HUMAN_INPUT
        t_human_withdraw = 0.2;
        comp_sel =1;
    case BALL_WISH_WITH_OPPOSITE_HUMAN_INPUT
        t_human_withdraw = 0.5;
        comp_sel =2;
    case REST_WISH_WITHOUT_HUMAN_INPUT
        t_human_withdraw = 0.0;
    case REST_WISH_WITH_HUMAN_INPUT
        t_human_withdraw = 0.7;
        comp_sel =2;
    case REST_WISH_WITH_OPPOSITE_HUMAN_INPUT
        t_human_withdraw = 0.5;
        comp_sel =1;
    case CHANGE_WISHES
        t_human_withdraw = 5;
        comp_sel =1;
        use_bad_man_speed = true;
end
component_stDim = agents{1}.motionModel.stDim;
component_bDim = component_stDim + component_stDim^2 + 1;
shared_uDim = 2;
component_alone_uDim = agents{1}.motionModel.ctDim - shared_uDim;

components_amount = length(b0)/component_bDim;
%     u_man = [u(end-shared_uDim+1);u(end)]
    
% stDim = motionModel.stDim;



% mu = cell(components_amount,1);
% sig = cell(components_amount,1);
% weight = zeros(components_amount,1);
mu_save = cell(components_amount,1);
sig_save = cell(components_amount,1);
weight_save = cell(components_amount,1);
x_save = [];
x_true = [];
[mu, sig, weight] = b2xPw(b0, component_stDim, components_amount);
for i_comp=1:components_amount
%     b0_comp = b0((i_comp-1)*component_bDim+1:i_comp*component_bDim);
%     mu{i_comp} = b0_comp(1:component_stDim);
%     for d = 1:motionModel.stDim
%         sig{i_comp}(:,d) = b0_comp(d*component_stDim+1:(d+1)*component_stDim, 1);
%     end
%     weight(i_comp) = b0_comp(end);
    if comp_sel == i_comp
        x_true = mu{i_comp};% + chol(sig{i_comp})' * randn(component_stDim,1);
        x_save = x_true;
    end
    mu_save{i_comp} = mu{i_comp};
    sig_save{i_comp} = sig{i_comp}(:);
    weight_save{i_comp} = weight(i_comp);
end

failed = 0;
b = b0;
for k = 1:nSteps-1

%     b = zeros(component_bDim*components_amount,1); % current belief
%     for i_comp=1:components_amount
%         b((i_comp-1)*component_bDim+1:(i_comp-1)*component_bDim+component_stDim)=mu{i_comp};
%         b((i_comp-1)*component_bDim+component_stDim+1:(i_comp-1)*component_bDim+component_stDim+component_stDim*component_stDim)=sig{i_comp};
%         b((i_comp)*component_bDim)=weight(i_comp);
%     end
%     b = xPw2b(mu, sig, weight, component_stDim, components_amount);
    
    u = agents{1}.getNextControl(b);
    %% update physical part
%     processNoise = motionModel.generateProcessNoise(x_true,u);
    zeroProcessNoise = zeros(4,1);
    % here we only use the input of comp_sel, drop the other target
    % u_for_true includes one target and the assist
    u_for_true = [u((comp_sel-1)*components_amount + 1:comp_sel*components_amount);u(end-1:end)];
    x_next_no_spec_human_motion = agents{1}.motionModel.evolve(x_true,u_for_true,zeroProcessNoise);
        
    good_man_for_ball_should_output = agents{1}.obsModel.getObservation(x_true,'nonoise');
    good_man_speed_angle=good_man_for_ball_should_output(1:2);
    v_man = [good_man_speed_angle(1)*cos(good_man_speed_angle(2));
                good_man_speed_angle(1)*sin(good_man_speed_angle(2))];
    
    if use_bad_man_speed
        if comp_sel ==1
            v_man=[0.7;-0.2]*0.94^(k*agents{1}.motionModel.dt*20)*6;
            if k*agents{1}.motionModel.dt>1
                v_man=[0.15;0.5]*0.94^((k-nSteps/6)*agents{1}.motionModel.dt*20)*6;
            end
            if k*agents{1}.motionModel.dt>2.6
                v_man=[-0.9;0.1]*0.94^((k-nSteps/3)*agents{1}.motionModel.dt*20)*6;
            end
            if k*agents{1}.motionModel.dt>4.5
                v_man=[0.45;-1.4]*0.94^((k-nSteps/3*2)*agents{1}.motionModel.dt*20)*6;
            end
        elseif comp_sel ==2
            v_man = [-1.1;1.]*0.94^(k*agents{1}.motionModel.dt*20)*0.3;
        end
        if k*agents{1}.motionModel.dt>t_human_withdraw
            v_man=[0;0];
        end
    else
        if k*agents{1}.motionModel.dt>t_human_withdraw
            v_man=[0;0];
        end
    end
    last_human_pos = x_true(3:4);
    x_true(1:2) = x_next_no_spec_human_motion(1:2);
    x_true(3:4) = last_human_pos + agents{1}.motionModel.dt*v_man + agents{1}.motionModel.dt*u_for_true(3:4);
    
        % Get observation model jacobians
    z = agents{1}.obsModel.getObservation(x_true,'truenoise'); % true observation
    %truely observed output is not the one modeled by ekf
    speed_man = norm(v_man);
    direction_man = atan2(v_man(2),v_man(1));
    %very problematic when human gives no more output
    z(1:2)=[speed_man;direction_man] + chol(agents{1}.obsModel.R_speed)' * randn(2,1);
    
    %% now do the machine part
    [b_next,mu,sig,weight] = agents{1}.getNextEstimation(b,u,z);
    b=b_next;
    %% now for save
    for i_comp = 1 : components_amount
        mu_save{i_comp}(:,k+1) = mu{i_comp};
        sig_save{i_comp}(:,k+1) = sig{i_comp}(:);
        weight_save{i_comp}(:,k+1) = weight(i_comp);
    end
    x_save(:,k+1) = x_true;
    x_true_final = x_true;

    
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
    figure(5)
    plot(x_save(1,k),x_save(2,k),'.')
    hold on
    axis equal
    plot(x_save(3,k),x_save(4,k),'+')
%     plot(mu_save{1}(3,k),mu_save{1}(4,k),'bo')
    plot(mu_save{1}(1,k),mu_save{1}(2,k),'bo')
    plot(mu_save{2}(1,k),mu_save{2}(2,k),'ro')
    
    pointsToPlot = drawResultGMM([mu_save{1}(:,k); sig_save{1}(:,k)], agents{1}.motionModel.stDim);
    plot(pointsToPlot(1,:),pointsToPlot(2,:),'b')
    pointsToPlot = drawResultGMM([mu_save{2}(:,k); sig_save{2}(:,k)], agents{1}.motionModel.stDim);
    plot(pointsToPlot(1,:),pointsToPlot(2,:),'r')
%     [x_nom, P_nom, w_nom] = b2xPw(b_nom(:,k), component_stDim, components_amount);
%     plot(x_save(1,k),x_save(2,k),'.')
%     hold on
%     axis equal
%     plot(x_nom{1}(3),x_nom{1}(4),'b+')
%     plot(x_nom{2}(3),x_nom{2}(4),'r+')
% %     plot(mu_save{1}(3,k),mu_save{1}(4,k),'bo')
%     plot(x_nom{1}(1),x_nom{1}(2),'bo')
%     plot(x_nom{2}(1),x_nom{2}(2),'ro')
%     
%     pointsToPlot = drawResultGMM(b_nom(1:20,k), motionModel.stDim);
%     plot(pointsToPlot(1,:),pointsToPlot(2,:),'b')
%     pointsToPlot = drawResultGMM(b_nom(22:41,k), motionModel.stDim);
%     plot(pointsToPlot(1,:),pointsToPlot(2,:),'r')
    figure(6)
%     
    plot([time_past + agents{1}.motionModel.dt*(k-1),time_past + agents{1}.motionModel.dt*(k)],[weight_save{1}(k),weight_save{1}(k+1)],'-ob',[time_past + agents{1}.motionModel.dt*(k-1),time_past + agents{1}.motionModel.dt*(k)],[weight_save{2}(k),weight_save{2}(k+1)],'-ok')
    hold on
%     time_line = 0:motionModel.dt:motionModel.dt*(nSteps);
    figure(10)
    subplot(2,2,1)
    plot(time_past + agents{1}.motionModel.dt*(k-1),u(5),'b.',time_past + agents{1}.motionModel.dt*(k-1),u(6),'r.')
    hold on
    subplot(2,2,2)
    plot(time_past + agents{1}.motionModel.dt*(k-1),v_man(1),'b.',time_past + agents{1}.motionModel.dt*(k-1),v_man(2),'r.')
    hold on
    subplot(2,2,3)
    plot(time_past + agents{1}.motionModel.dt*(k-1),u(1),'b.',time_past + agents{1}.motionModel.dt*(k-1),u(2),'r.')
    hold on
    subplot(2,2,4)
    plot(time_past + agents{1}.motionModel.dt*(k-1),u(3),'b.',time_past + agents{1}.motionModel.dt*(k-1),u(4),'r.')
    hold on
    pause(0.02);
end
b_f = b_next;
if time_past<0.01
    figure(10)
    subplot(2,2,1)
    title('Unterstützung Plattform')
    xlabel('t(s)')
    ylabel('vel(m/s)')
%     legend('x','y')
    grid
    % hold off
    subplot(2,2,2)
    title('Mensch selbst')
    xlabel('t(s)')
    ylabel('vel(m/s)')
%     legend('x','y')
    grid
    % hold off
    subplot(2,2,3)
    title('Bewegung des Ziels A')
    xlabel('t(s)')
    ylabel('vel(m/s)')
%     legend('x','y')
    grid
    % hold off
    subplot(2,2,4)
    title('Bewegung des Ziels B')
    xlabel('t(s)')
    ylabel('vel(m/s)')
%     legend('x','y')
    grid

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
    figure(5)
    title('Bewegungen von Plattform, Ziel A und Ziel B')
    xlabel('x(m)')
    ylabel('y(m)')
%     legend('wahre Ziele','Plattform','Ziel A im Filter','Ziel B im Filter')
    % hold off
    figure(6)
    title('Gewicht der Wünsche')
    xlabel('t(s)')
    ylabel('Gewicht')
%     legend('A','B')
end
end